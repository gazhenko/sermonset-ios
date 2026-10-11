ALTER TABLE accounts ADD COLUMN credit_opt_in INTEGER NOT NULL DEFAULT 0;
CREATE TABLE ownership_events (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
 version INTEGER NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN ('minted','transferred')),
 from_account TEXT REFERENCES accounts(id) ON DELETE SET NULL,
 to_account TEXT REFERENCES accounts(id) ON DELETE SET NULL,
 occurred_at TEXT NOT NULL,
 UNIQUE(card_id,version)
);
-- Existing journey rows are actual recorded ownership events, including hidden rows.
INSERT INTO ownership_events(card_id,version,kind,from_account,to_account,occurred_at)
SELECT card_id,ROW_NUMBER() OVER (PARTITION BY card_id ORDER BY id),
 CASE WHEN ROW_NUMBER() OVER (PARTITION BY card_id ORDER BY id)=1 THEN 'minted' ELSE 'transferred' END,
 LAG(participant_id) OVER (PARTITION BY card_id ORDER BY id),participant_id,occurred_at FROM journey_events;
CREATE TRIGGER ownership_mint AFTER INSERT ON cards BEGIN
 INSERT INTO ownership_events(card_id,version,kind,to_account,occurred_at) VALUES(NEW.id,NEW.version,'minted',NEW.owner_id,NEW.created_at);
END;
CREATE TRIGGER ownership_transfer AFTER UPDATE OF owner_id ON cards WHEN OLD.owner_id<>NEW.owner_id BEGIN
 INSERT INTO ownership_events(card_id,version,kind,from_account,to_account,occurred_at)
 VALUES(NEW.id,NEW.version,'transferred',OLD.owner_id,NEW.owner_id,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
END;
