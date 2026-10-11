import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { harness, metadata } from "./harness.mjs";

async function inboxRows(h, resourceID) {
  return (
    await h.db
      .prepare(
        "SELECT account_id,type FROM inbox WHERE resource_id=? ORDER BY account_id,type",
      )
      .bind(resourceID)
      .all()
  ).results;
}

function notification(account, type) {
  return { account_id: account.id, type };
}

test("offer actions notify only the other party, including bearer offers and retries", async (t) => {
  const h = await harness();
  t.after(h.close);
  for (const bound of [true, false]) {
    for (const kind of ["gift", "swap"]) {
      const actions =
        kind === "gift"
          ? ["cancel", "decline", "accept"]
          : ["propose", "confirm", "cancel", "decline"];
      for (const action of actions) {
        await t.test(
          `${bound ? "bound" : "bearer"} ${kind} ${action}`,
          async () => {
            const sender = await h.account("Sender"),
              recipient = await h.account("Recipient");
            const card = await h.call(
              sender,
              "POST",
              "/v1/sermons/sample-peace-in-the-storm/keep",
              { source: "discover" },
            );
            const offer = await h.call(sender, "POST", "/v1/offers", {
              kind,
              cardID: card.cardID,
              cardVersion: 1,
              ...(bound ? { recipientID: recipient.id } : {}),
            });
            const prior = bound
              ? [notification(recipient, "offerReceived")]
              : [];
            assert.deepEqual(await inboxRows(h, offer.offerID), prior);
            const token = bound ? {} : { token: offer.token };
            let proposal;
            if (kind === "swap") {
              const otherCard = await h.call(
                recipient,
                "POST",
                "/v1/sermons/sample-when-faith-gets-loud/keep",
                { source: "discover" },
              );
              proposal = { ...token, cardID: otherCard.cardID, cardVersion: 1 };
              if (action !== "propose") {
                await h.call(
                  recipient,
                  "POST",
                  `/v1/offers/${offer.offerID}/propose`,
                  proposal,
                );
                prior.push(notification(sender, "offerProposed"));
              }
            }
            const actor = ["cancel", "confirm"].includes(action)
                ? sender
                : recipient,
              other = actor === sender ? recipient : sender;
            const before = await h.call(actor, "GET", "/v1/inbox");
            const body =
                action === "propose" ? proposal : actor === sender ? {} : token,
              path = `/v1/offers/${offer.offerID}/${action}`,
              key = randomUUID();
            const result = await h.call(actor, "POST", path, body, { key });
            assert.deepEqual(
              await h.call(actor, "POST", path, body, { key }),
              result,
            );
            assert.deepEqual(await h.call(actor, "GET", "/v1/inbox"), before);
            const type = {
              cancel: "offerCancelled",
              decline: "offerDeclined",
              accept: "offerAccepted",
              propose: "offerProposed",
              confirm: "offerAccepted",
            }[action];
            // Cancelling an unclaimed bearer gift has no other account to notify.
            const expected = [...prior];
            if (bound || actor === recipient || kind === "swap")
              expected.push(notification(other, type));
            expected.sort(
              (a, b) =>
                a.account_id.localeCompare(b.account_id) ||
                a.type.localeCompare(b.type),
            );
            assert.deepEqual(await inboxRows(h, offer.offerID), expected);
          },
        );
      }
    }
  }
});

test("publication decisions skip the reviewer when they are also the contributor", async (t) => {
  const h = await harness();
  t.after(h.close);
  for (const church of [false, true]) {
    for (const self of [false, true]) {
      for (const decision of ["approve", "reject"]) {
        await t.test(
          `${church ? "church" : "moderation"} ${self ? "own" : "other"} ${decision}`,
          async () => {
            const contributor = await h.account("Contributor"),
              reviewer = self ? contributor : await h.account("Reviewer");
            if (church) await h.staff(reviewer);
            else await h.admin(reviewer);
            const pub = await h.call(
              contributor,
              "POST",
              "/v1/publications",
              metadata(),
            );
            if (church) {
              await h.call(
                reviewer,
                "POST",
                `/v1/portal/churches/sample-church-west/publications/${pub.publicationID}/decision`,
                { decision, reason: "Reviewed fixture metadata" },
              );
            } else {
              await h.call(reviewer, "POST", "/v1/moderation/actions", {
                targetType: "publication",
                targetID: pub.publicationID,
                action: decision,
                reason: "Reviewed fixture metadata",
              });
            }
            const types = church
              ? decision === "approve"
                ? ["churchDecision", "publicationPublished"]
                : ["churchDecision"]
              : [
                  decision === "approve"
                    ? "publicationPublished"
                    : "publicationRejected",
                ];
            assert.deepEqual(
              await inboxRows(h, pub.publicationID),
              self ? [] : types.map((type) => notification(contributor, type)),
            );
            assert.deepEqual(
              (await h.call(reviewer, "GET", "/v1/inbox")).items,
              [],
            );
          },
        );
      }
    }
  }
});

test("claim, report and appeal resolutions notify an affected account only for another actor", async (t) => {
  const h = await harness();
  t.after(h.close);
  for (const type of ["claim", "report", "appeal"]) {
    for (const self of [false, true]) {
      await t.test(
        `${type} resolved by ${self ? "own" : "other"} account`,
        async () => {
          const affected = await h.account("Affected account"),
            reviewer = self ? affected : await h.account("Reviewer");
          await h.admin(reviewer);
          let targetID;
          if (type === "claim") {
            targetID = (
              await h.call(affected, "POST", "/v1/church-claims", {
                churchID: "sample-church-west",
                name: "Fictional church",
                website: "https://example.invalid",
                role: "Pastor",
                evidence: "Fixture verification evidence",
              })
            ).claimID;
          } else if (type === "report") {
            targetID = (
              await h.call(affected, "POST", "/v1/reports", {
                targetType: "sermon",
                targetID: "sample-peace-in-the-storm",
                reason: "privacy",
              })
            ).reportID;
          } else {
            const moderator = await h.account("Original moderator");
            await h.admin(moderator);
            const pub = await h.call(
              affected,
              "POST",
              "/v1/publications",
              metadata(),
            );
            const rejection = await h.call(
              moderator,
              "POST",
              "/v1/moderation/actions",
              {
                targetType: "publication",
                targetID: pub.publicationID,
                action: "reject",
                reason: "Review fixture",
              },
            );
            targetID = (
              await h.call(affected, "POST", "/v1/appeals", {
                actionID: rejection.actionID,
                reason: "Please review",
              })
            ).appealID;
          }
          assert.deepEqual(await inboxRows(h, targetID), []);
          const before = await h.call(reviewer, "GET", "/v1/inbox");
          await h.call(reviewer, "POST", "/v1/moderation/actions", {
            targetType: type,
            targetID,
            action: type === "claim" ? "approve" : "resolve",
            reason: "Reviewed fixture",
          });
          assert.deepEqual(await h.call(reviewer, "GET", "/v1/inbox"), before);
          assert.deepEqual(
            await inboxRows(h, targetID),
            self
              ? []
              : [
                  notification(
                    affected,
                    type === "claim"
                      ? "churchClaimApproved"
                      : `${type}Resolved`,
                  ),
                ],
          );
        },
      );
    }
  }
});

test("sermon moderation skips the acting contributor and still notifies other contributors", async (t) => {
  const h = await harness();
  t.after(h.close);
  for (const self of [false, true]) {
    await t.test(
      self ? "own sermon" : "another contributor's sermon",
      async () => {
        const contributor = await h.account("Contributor"),
          moderator = self ? contributor : await h.account("Moderator");
        await h.admin(moderator);
        const pub = await h.call(
          contributor,
          "POST",
          "/v1/publications",
          // Canonical matching uses either title or passage; isolate both scenarios.
          metadata({ title: randomUUID(), primaryPassage: randomUUID() }),
        );
        await h.call(moderator, "POST", "/v1/moderation/actions", {
          targetType: "publication",
          targetID: pub.publicationID,
          action: "approve",
          reason: "Reviewed metadata",
        });
        const before = await h.call(moderator, "GET", "/v1/inbox");
        const expected = [];
        for (const action of ["dispute", "remove", "restore"]) {
          await h.call(moderator, "POST", "/v1/moderation/actions", {
            targetType: "sermon",
            targetID: pub.sermonID,
            action,
            reason: "Fixture moderation",
          });
          if (!self)
            expected.push(
              notification(
                contributor,
                `moderation${action[0].toUpperCase()}${action.slice(1)}`,
              ),
            );
          expected.sort((a, b) => a.type.localeCompare(b.type));
          assert.deepEqual(await inboxRows(h, pub.sermonID), expected);
          assert.deepEqual(await h.call(moderator, "GET", "/v1/inbox"), before);
        }
      },
    );
  }
});
