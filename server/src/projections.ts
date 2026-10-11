import type { Env, Row } from "./types";
import { one } from "./common";
export const authorizedSQL = `a.state='published' AND a.validated=1 AND a.uploaded=1 AND g.active=1
 AND g.church_id=(SELECT church_id FROM sermons WHERE id=a.sermon_id)
 AND (g.expires_at IS NULL OR julianday(g.expires_at)>julianday('now'))
 AND (g.service_id IS NULL OR EXISTS(SELECT 1 FROM services sv WHERE sv.id=g.service_id AND sv.revoked=0 AND sv.public_sharing_allowed=1 AND julianday(sv.expires_at)>julianday('now')))`;
export const sermonSelect = `SELECT s.*,EXISTS(SELECT 1 FROM audio_assets a JOIN grants g ON g.asset_id=a.id
 WHERE a.id=s.canonical_audio_id AND ${authorizedSQL} AND s.state='published') AS audio_available,
 (SELECT kind FROM audio_assets WHERE id=s.canonical_audio_id) AS audio_kind FROM sermons s`;
export function sermon(row: Row): Row {
  const labels = ["Community matched"];
  if (row.church_verified) labels.push("Church verified");
  if (row.audio_available)
    labels.push(
      row.audio_kind === "official" ? "Official audio" : "Audio authorized",
    );
  if (row.state === "disputed") labels.push("Disputed");
  if (row.state === "removed") labels.push("Audio removed");
  return {
    id: row.id,
    churchID: row.church_id,
    title: row.title,
    preacher: row.preacher,
    service: row.service,
    serviceDate: row.service_date,
    primaryPassage: row.primary_passage,
    themes: JSON.parse(row.themes),
    sermonType: row.sermon_type,
    city: row.city,
    region: row.region,
    country: row.country,
    summary: row.summary,
    reflectionPrompt: row.reflection_prompt,
    state: row.state,
    trustLabels: labels,
    audioAvailable: !!row.audio_available,
    canonicalAudioAssetID: row.canonical_audio_id,
    fictional: !!row.fictional,
    createdAt: row.created_at,
  };
}
export const getSermon = async (env: Env, id: string) =>
  sermon(
    await one(
      env,
      `${sermonSelect} WHERE s.id=? AND s.state IN ('published','disputed','removed')`,
      id,
    ),
  );
export function church(row: Row): Row {
  return {
    id: row.id,
    name: row.name,
    city: row.city,
    region: row.region,
    country: row.country,
    website: row.website,
    verified: !!row.verified,
    creditPolicy: row.credit_policy,
    fictional: !!row.fictional,
  };
}
export const cardSelect = `SELECT c.*,e.sermon_id,e.type FROM cards c JOIN editions e ON e.id=c.edition_id`;
export function card(row: Row): Row {
  return {
    id: row.id,
    sermonID: row.sermon_id,
    editionID: row.edition_id,
    edition: row.type,
    serialNumber: row.serial_number,
    ownerID: row.owner_id,
    version: row.version,
    tradeable: true,
    createdAt: row.created_at,
  };
}
export function publication(row: Row): Row {
  return {
    id: row.id,
    sermonID: row.sermon_id,
    state: row.state,
    audioAssetID: row.audio_asset_id,
    createdAt: row.created_at,
  };
}
export const reviewSelect = `SELECT p.*,a.duration,a.byte_count,
 CASE WHEN EXISTS(SELECT 1 FROM blocks b WHERE (b.account_id=? AND b.blocked_id=p.account_id) OR (b.blocked_id=? AND b.account_id=p.account_id)) THEN NULL ELSE ac.display_name END AS contributor_name
 FROM publications p LEFT JOIN audio_assets a ON a.id=p.audio_asset_id LEFT JOIN accounts ac ON ac.id=p.account_id`;
export function reviewedPublication(row: Row): Row {
  const metadata = JSON.parse(row.review_metadata);
  return {
    ...publication(row),
    review: {
      title: metadata.title ?? "",
      preacher: metadata.preacher ?? "",
      serviceDate: metadata.serviceDate ?? "",
      primaryPassage: metadata.primaryPassage ?? "",
      sermonType: metadata.sermonType ?? "",
      themes: metadata.themes ?? [],
      summary: metadata.summary ?? null,
      reflectionPrompt: metadata.reflectionPrompt ?? null,
      rightsBasis: row.rights_basis,
      checklist: metadata.checklist ?? null,
      audio: row.audio_asset_id
        ? { duration: row.duration, byteCount: row.byte_count }
        : null,
      contributorDisplayName: row.contributor_name ?? null,
    },
  };
}
export function offer(row: Row): Row {
  return {
    id: row.id,
    kind: row.kind,
    senderID: row.sender_id,
    recipientID: row.recipient_id,
    cardID: row.card_id,
    cardVersion: row.card_version,
    proposedCardID: row.proposed_card_id,
    proposedCardVersion: row.proposed_card_version,
    message: row.message,
    state:
      ["open", "proposed"].includes(row.state) &&
      Date.parse(row.expires_at) <= Date.now()
        ? "expired"
        : row.state,
    expiresAt: row.expires_at,
    createdAt: row.created_at,
  };
}
export function audit(row: Row): Row {
  return {
    id: row.id,
    actorID: row.actor_id,
    targetType: row.target_type,
    targetID: row.target_id,
    action: row.action,
    reason: row.reason,
    createdAt: row.created_at,
  };
}
export function claim(row: Row): Row {
  return {
    id: row.id,
    accountID: row.account_id,
    churchID: row.church_id,
    name: row.name,
    website: row.website,
    role: row.role,
    evidence: row.evidence,
    state: row.state,
    createdAt: row.created_at,
  };
}
export function appeal(row: Row): Row {
  return {
    id: row.id,
    accountID: row.account_id,
    actionID: row.action_id,
    reason: row.reason,
    state: row.state,
    createdAt: row.created_at,
  };
}
export function report(row: Row): Row {
  return {
    id: row.id,
    reporterID: row.reporter_id,
    targetType: row.target_type,
    targetID: row.target_id,
    reason: row.reason,
    timestamp: row.timestamp,
    details: row.details,
    state: row.state,
    createdAt: row.created_at,
    targetSummary: row.target_summary ?? "Unavailable target",
  };
}
