-- The request transaction writes acceptance notifications with the acting account.
-- Keep transfers and all ownership guards here, without actor-blind inbox writes.
DROP TRIGGER offer_transfer;
CREATE TRIGGER offer_transfer BEFORE UPDATE OF state ON offers WHEN NEW.state='accepted' AND OLD.state<>NEW.state BEGIN
 SELECT RAISE(ABORT,'expired') WHERE julianday(OLD.expires_at)<=julianday('now');
 SELECT RAISE(ABORT,'invalid_recipient') WHERE NEW.recipient_id IS NULL OR NEW.recipient_id=NEW.sender_id;
 SELECT RAISE(ABORT,'conflict') WHERE (OLD.kind='gift' AND OLD.state<>'open') OR (OLD.kind='swap' AND OLD.state<>'proposed');
 SELECT RAISE(ABORT,'blocked') WHERE EXISTS(SELECT 1 FROM blocks WHERE (account_id=NEW.sender_id AND blocked_id=NEW.recipient_id) OR
 (account_id=NEW.recipient_id AND blocked_id=NEW.sender_id));
 SELECT RAISE(ABORT,'forbidden') WHERE EXISTS(SELECT 1 FROM accounts WHERE id IN (NEW.sender_id,NEW.recipient_id) AND banned=1);
 SELECT RAISE(ABORT,'stale_version') WHERE NOT EXISTS(SELECT 1 FROM cards WHERE id=OLD.card_id AND owner_id=OLD.sender_id AND version=OLD.card_version);
 SELECT RAISE(ABORT,'stale_version') WHERE OLD.kind='swap' AND NOT EXISTS(SELECT 1 FROM cards WHERE id=OLD.proposed_card_id AND owner_id=OLD.recipient_id AND version=OLD.proposed_card_version);
 UPDATE cards SET owner_id=NEW.recipient_id,version=version+1 WHERE id=OLD.card_id;
 UPDATE cards SET owner_id=NEW.sender_id,version=version+1 WHERE OLD.kind='swap' AND id=OLD.proposed_card_id;
END;
