PRAGMA foreign_keys = ON;
CREATE TABLE accounts (
 id TEXT PRIMARY KEY, public_key TEXT NOT NULL, key_fingerprint TEXT NOT NULL UNIQUE,
 display_name TEXT, avatar_style TEXT NOT NULL DEFAULT 'plain', banned INTEGER NOT NULL DEFAULT 0,
 journey_opt_in INTEGER NOT NULL DEFAULT 0, journey_city TEXT, created_at TEXT NOT NULL
);
CREATE TABLE roles (account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 role TEXT NOT NULL CHECK(role IN ('listener','churchStaff','moderator','admin')), church_id TEXT NOT NULL DEFAULT '',
 PRIMARY KEY(account_id,role,church_id));
CREATE TABLE nonces (account_id TEXT NOT NULL, nonce TEXT NOT NULL, expires INTEGER NOT NULL, PRIMARY KEY(account_id,nonce));
CREATE TABLE commands (account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 key TEXT NOT NULL, hash TEXT NOT NULL, response TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(account_id,key));
CREATE TABLE mutation_guard (ok INTEGER NOT NULL CHECK(ok=1));
CREATE TABLE link_codes (hash TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, expires INTEGER NOT NULL);
CREATE TABLE sessions (hash TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, csrf TEXT NOT NULL, expires INTEGER NOT NULL);
CREATE TABLE churches (id TEXT PRIMARY KEY, name TEXT NOT NULL, city TEXT, region TEXT, country TEXT,
 website TEXT, verified INTEGER NOT NULL DEFAULT 0, credit_policy TEXT NOT NULL DEFAULT 'anonymous' CHECK(credit_policy IN ('named','anonymous')),
 fictional INTEGER NOT NULL DEFAULT 0);
CREATE TABLE sermons (id TEXT PRIMARY KEY, church_id TEXT REFERENCES churches(id), title TEXT NOT NULL, title_normalized TEXT NOT NULL,
 preacher TEXT NOT NULL, service TEXT, service_date TEXT NOT NULL, primary_passage TEXT NOT NULL, passage_normalized TEXT NOT NULL,
 themes TEXT NOT NULL, sermon_type TEXT NOT NULL, city TEXT, region TEXT, country TEXT, summary TEXT, reflection_prompt TEXT,
 state TEXT NOT NULL DEFAULT 'pendingRights', canonical_audio_id TEXT, church_verified INTEGER NOT NULL DEFAULT 0,
 fictional INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
CREATE INDEX sermon_match ON sermons(church_id,service_date,title_normalized,passage_normalized);
CREATE INDEX sermon_feed ON sermons(state,created_at,id);
CREATE TABLE services (id TEXT PRIMARY KEY, church_id TEXT NOT NULL REFERENCES churches(id), service TEXT NOT NULL,
 starts_at TEXT NOT NULL, recording_allowed INTEGER NOT NULL, public_sharing_allowed INTEGER NOT NULL,
 review_required INTEGER NOT NULL, expires_at TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, token TEXT NOT NULL);
CREATE TABLE publications (id TEXT PRIMARY KEY, account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
 sermon_id TEXT NOT NULL REFERENCES sermons(id), state TEXT NOT NULL, rights_basis TEXT NOT NULL,
 service_id TEXT REFERENCES services(id), audio_asset_id TEXT, created_at TEXT NOT NULL);
CREATE TABLE audio_assets (id TEXT PRIMARY KEY, publication_id TEXT NOT NULL REFERENCES publications(id),
 owner_id TEXT REFERENCES accounts(id) ON DELETE SET NULL, sermon_id TEXT NOT NULL REFERENCES sermons(id),
 storage_key TEXT NOT NULL UNIQUE, checksum TEXT NOT NULL, source_checksum TEXT NOT NULL,
 byte_count INTEGER NOT NULL, duration REAL NOT NULL, trim_start REAL NOT NULL, trim_end REAL NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN ('enhancedCommunity','official')), state TEXT NOT NULL,
 uploaded INTEGER NOT NULL DEFAULT 0, validated INTEGER NOT NULL DEFAULT 0, upload_expires INTEGER NOT NULL);
CREATE TABLE grants (asset_id TEXT PRIMARY KEY REFERENCES audio_assets(id), church_id TEXT NOT NULL REFERENCES churches(id),
 service_id TEXT REFERENCES services(id), grantor_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
 active INTEGER NOT NULL DEFAULT 1, expires_at TEXT, basis TEXT NOT NULL);
CREATE TABLE contributors (sermon_id TEXT NOT NULL REFERENCES sermons(id), account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 PRIMARY KEY(sermon_id,account_id));
CREATE TABLE editions (id TEXT PRIMARY KEY, sermon_id TEXT NOT NULL REFERENCES sermons(id), type TEXT NOT NULL CHECK(type IN ('Community','Church')),
 next_serial INTEGER NOT NULL DEFAULT 0, UNIQUE(sermon_id,type));
CREATE TABLE history (account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, sermon_id TEXT NOT NULL REFERENCES sermons(id),
 source TEXT NOT NULL CHECK(source IN ('discover','pack','trade','shared')), first_encountered_at TEXT NOT NULL,
 PRIMARY KEY(account_id,sermon_id));
CREATE TABLE cards (id TEXT PRIMARY KEY, edition_id TEXT NOT NULL REFERENCES editions(id), owner_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 serial_number INTEGER NOT NULL, version INTEGER NOT NULL DEFAULT 1, source TEXT NOT NULL, created_at TEXT NOT NULL,
 UNIQUE(edition_id,serial_number));
CREATE TABLE keep_mints (account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, sermon_id TEXT NOT NULL REFERENCES sermons(id), card_id TEXT NOT NULL,
 PRIMARY KEY(account_id,sermon_id));
CREATE TABLE offers (id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('gift','swap')), sender_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 recipient_id TEXT REFERENCES accounts(id) ON DELETE CASCADE, card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE, card_version INTEGER NOT NULL,
 proposed_card_id TEXT REFERENCES cards(id) ON DELETE CASCADE, proposed_card_version INTEGER, message TEXT,
 state TEXT NOT NULL DEFAULT 'open' CHECK(state IN ('open','proposed','accepted','declined','cancelled','expired')),
 expires_at TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE blocks (account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, blocked_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 PRIMARY KEY(account_id,blocked_id));
CREATE TABLE inbox (id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 type TEXT NOT NULL, resource_id TEXT NOT NULL, created_at TEXT NOT NULL, read INTEGER NOT NULL DEFAULT 0);
CREATE TABLE journey_events (id INTEGER PRIMARY KEY AUTOINCREMENT, card_id TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
 participant_id TEXT REFERENCES accounts(id) ON DELETE SET NULL, city TEXT, occurred_at TEXT NOT NULL, hidden INTEGER NOT NULL DEFAULT 0);
CREATE INDEX journey_card ON journey_events(card_id,id);
CREATE TABLE journey_cohorts (city TEXT PRIMARY KEY, cards INTEGER NOT NULL);
CREATE TABLE pack_pools (week TEXT PRIMARY KEY, season TEXT NOT NULL, sermon_ids TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE packs (account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, week TEXT NOT NULL, season TEXT NOT NULL,
 sermon_ids TEXT NOT NULL, opened INTEGER NOT NULL DEFAULT 0, fallback INTEGER NOT NULL, PRIMARY KEY(account_id,week));
CREATE TABLE reports (id TEXT PRIMARY KEY, reporter_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
 target_type TEXT NOT NULL, target_id TEXT NOT NULL, reason TEXT NOT NULL, timestamp REAL, details TEXT, state TEXT NOT NULL DEFAULT 'open', created_at TEXT NOT NULL);
CREATE TABLE claims (id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 church_id TEXT REFERENCES churches(id), name TEXT NOT NULL, website TEXT NOT NULL, role TEXT NOT NULL, evidence TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'open', created_at TEXT NOT NULL);
CREATE TABLE audit (id TEXT PRIMARY KEY, actor_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
 affected_account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
 target_type TEXT NOT NULL, target_id TEXT NOT NULL, action TEXT NOT NULL, reason TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE appeals (id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 action_id TEXT NOT NULL REFERENCES audit(id), reason TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'open', created_at TEXT NOT NULL);
CREATE TABLE removals (id TEXT PRIMARY KEY, church_id TEXT NOT NULL REFERENCES churches(id), sermon_id TEXT NOT NULL REFERENCES sermons(id),
 account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL, reason TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE shares (id TEXT PRIMARY KEY, account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
 sermon_id TEXT NOT NULL REFERENCES sermons(id), storage_key TEXT NOT NULL UNIQUE,
 byte_count INTEGER NOT NULL, checksum TEXT NOT NULL, uploaded INTEGER NOT NULL DEFAULT 0, upload_expires INTEGER NOT NULL);
CREATE TABLE deletion_jobs (bucket TEXT NOT NULL, storage_key TEXT NOT NULL, PRIMARY KEY(bucket,storage_key));

-- Mint serials and library associations in the same transaction as ownership.
CREATE TRIGGER card_minted AFTER INSERT ON cards BEGIN
 UPDATE editions SET next_serial=NEW.serial_number WHERE id=NEW.edition_id;
 INSERT OR IGNORE INTO history(account_id,sermon_id,source,first_encountered_at)
 SELECT NEW.owner_id,sermon_id,NEW.source,NEW.created_at FROM editions WHERE id=NEW.edition_id;
 INSERT INTO journey_events(card_id,participant_id,city,occurred_at)
 SELECT NEW.id,id,journey_city,NEW.created_at FROM accounts WHERE id=NEW.owner_id;
END;
CREATE TRIGGER card_transferred AFTER UPDATE OF owner_id ON cards WHEN OLD.owner_id<>NEW.owner_id BEGIN
 INSERT OR IGNORE INTO history(account_id,sermon_id,source,first_encountered_at)
 SELECT NEW.owner_id,sermon_id,'trade',strftime('%Y-%m-%dT%H:%M:%fZ','now') FROM editions WHERE id=NEW.edition_id;
 INSERT INTO journey_events(card_id,participant_id,city,occurred_at)
 SELECT NEW.id,id,journey_city,strftime('%Y-%m-%dT%H:%M:%fZ','now') FROM accounts WHERE id=NEW.owner_id;
END;
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
 INSERT INTO inbox(id,account_id,type,resource_id,created_at) VALUES(lower(hex(randomblob(16))),NEW.sender_id,'offerAccepted',NEW.id,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
 INSERT INTO inbox(id,account_id,type,resource_id,created_at) VALUES(lower(hex(randomblob(16))),NEW.recipient_id,'offerAccepted',NEW.id,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
END;
