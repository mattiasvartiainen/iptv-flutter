-- grp --
CREATE TABLE grp (id INTEGER PRIMARY KEY, ord INTEGER NOT NULL, category_id INTEGER NOT NULL, title TEXT NOT NULL, type TEXT NOT NULL);

-- video --
CREATE TABLE video (id INTEGER PRIMARY KEY, group_id INTEGER NOT NULL, ord INTEGER NOT NULL, type TEXT NOT NULL, source TEXT NOT NULL, title TEXT NOT NULL, link TEXT NOT NULL, image_url TEXT NOT NULL, lang TEXT, added_time INTEGER, epg_id TEXT, stream_id INTEGER, tv_archive INTEGER NOT NULL, rating REAL, tmdb_id TEXT, serie_id INTEGER, cover_url TEXT, plot TEXT, cast_members TEXT, genre TEXT, youtube_trailer TEXT, last_modified INTEGER, release_date INTEGER, backdrop_paths TEXT);

-- video_fts --
CREATE VIRTUAL TABLE video_fts USING fts5(title, content='video', content_rowid='id', tokenize='trigram remove_diacritics 1');

-- video_fts_config --
CREATE TABLE 'video_fts_config'(k PRIMARY KEY, v) WITHOUT ROWID;

-- video_fts_data --
CREATE TABLE 'video_fts_data'(id INTEGER PRIMARY KEY, block BLOB);

-- video_fts_docsize --
CREATE TABLE 'video_fts_docsize'(id INTEGER PRIMARY KEY, sz BLOB);

-- video_fts_idx --
CREATE TABLE 'video_fts_idx'(segid, term, pgno, PRIMARY KEY(segid, term)) WITHOUT ROWID;

