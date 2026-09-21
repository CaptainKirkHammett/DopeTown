-- ============================================================================
-- DopeTown GA4 BigQuery Views
-- ============================================================================
-- Prerequisites:
--   1. Link your GA4 property (G-SDGS7PLXHZ) to BigQuery in GA4 Admin
--      Admin → Product Links → BigQuery Links → Link
--   2. Connect Looker / Looker Studio to these views as data sources
--
-- Deployment: PROJECT_ID and DATASET_ID below are placeholders, not real
-- values, on purpose - .github/workflows/deploy-bigquery-views.yml
-- substitutes them from GitHub secrets and runs this whole file against
-- BigQuery automatically on every push to main that touches this file.
-- Edit this file, push to main, and the views update themselves - no
-- copy-pasting into the BigQuery console needed. See that workflow file
-- for the one-time GCP service account setup it requires.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Base view: flattens every event with its common parameters
--    Use this as a general-purpose data source in Looker Studio.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `PROJECT_ID.DATASET_ID.v_all_events` AS
SELECT
  event_date,
  TIMESTAMP_MICROS(event_timestamp)                                      AS event_time,
  event_name,
  (SELECT value.string_value  FROM UNNEST(event_params) WHERE key = 'event_category')  AS event_category,
  (SELECT value.string_value  FROM UNNEST(event_params) WHERE key = 'event_label')     AS event_label,
  (SELECT value.string_value  FROM UNNEST(event_params) WHERE key = 'file_name')       AS file_name,
  (SELECT value.string_value  FROM UNNEST(event_params) WHERE key = 'file_extension')  AS file_extension,
  (SELECT value.string_value  FROM UNNEST(event_params) WHERE key = 'link_url')        AS link_url,
  (SELECT value.string_value  FROM UNNEST(event_params) WHERE key = 'page_location')   AS page_location,
  geo.country                                                            AS country,
  geo.city                                                               AS city,
  device.category                                                        AS device_category,
  device.operating_system                                                AS os,
  device.web_info.browser                                                AS browser,
  traffic_source.source                                                  AS traffic_source,
  traffic_source.medium                                                  AS traffic_medium,
  user_pseudo_id
FROM `PROJECT_ID.DATASET_ID.events_*`;


-- ----------------------------------------------------------------------------
-- 2. File downloads (VST installers, zips, WAV exports)
--    Covers: file_download_* and file_download_dope_box_pattern_wav
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `PROJECT_ID.DATASET_ID.v_file_downloads` AS
SELECT
  event_date,
  TIMESTAMP_MICROS(event_timestamp)                                      AS event_time,
  event_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'file_name')        AS file_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'file_extension')   AS file_extension,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'link_url')         AS link_url,
  geo.country                                                            AS country,
  device.category                                                        AS device_category,
  device.operating_system                                                AS os,
  user_pseudo_id
FROM `PROJECT_ID.DATASET_ID.events_*`
WHERE event_name LIKE 'file_download_%';


-- ----------------------------------------------------------------------------
-- 3. Social link clicks (Instagram, TikTok, Facebook, etc.)
--    Covers: social_click_insta, social_click_tiktok, social_click_facebook
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `PROJECT_ID.DATASET_ID.v_social_clicks` AS
SELECT
  event_date,
  TIMESTAMP_MICROS(event_timestamp)                                      AS event_time,
  event_name,
  REPLACE(event_name, 'social_click_', '')                               AS platform,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'event_label')      AS link_label,
  geo.country                                                            AS country,
  device.category                                                        AS device_category,
  user_pseudo_id
FROM `PROJECT_ID.DATASET_ID.events_*`
WHERE event_name LIKE 'social_click_%';


-- ----------------------------------------------------------------------------
-- 4. Dope Box (drum sequencer) engagement
--    Covers: dope_box_open, dope_box_play, dope_box_stop
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `PROJECT_ID.DATASET_ID.v_dope_box` AS
SELECT
  event_date,
  TIMESTAMP_MICROS(event_timestamp)                                      AS event_time,
  event_name,
  CASE event_name
    WHEN 'dope_box_open'  THEN 'open'
    WHEN 'dope_box_play'  THEN 'play'
    WHEN 'dope_box_stop'  THEN 'stop'
  END                                                                    AS action,
  geo.country                                                            AS country,
  device.category                                                        AS device_category,
  device.operating_system                                                AS os,
  user_pseudo_id
FROM `PROJECT_ID.DATASET_ID.events_*`
WHERE event_name IN ('dope_box_open', 'dope_box_play', 'dope_box_stop');


-- ----------------------------------------------------------------------------
-- 5. UI engagement (acid mode, background changes, embeds toggle)
--    Covers: acid_mode, background_change, embeds_hide
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `PROJECT_ID.DATASET_ID.v_ui_engagement` AS
SELECT
  event_date,
  TIMESTAMP_MICROS(event_timestamp)                                      AS event_time,
  event_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'event_label')      AS label,
  geo.country                                                            AS country,
  device.category                                                        AS device_category,
  user_pseudo_id
FROM `PROJECT_ID.DATASET_ID.events_*`
WHERE event_name IN ('acid_mode', 'background_change', 'embeds_hide');


-- ----------------------------------------------------------------------------
-- 6. Demo audio plays
--    Covers: demo_play
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `PROJECT_ID.DATASET_ID.v_demo_plays` AS
SELECT
  event_date,
  TIMESTAMP_MICROS(event_timestamp)                                      AS event_time,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'event_label')      AS demo_name,
  geo.country                                                            AS country,
  device.category                                                        AS device_category,
  device.operating_system                                                AS os,
  user_pseudo_id
FROM `PROJECT_ID.DATASET_ID.events_*`
WHERE event_name = 'demo_play';


-- ----------------------------------------------------------------------------
-- 6b. Music platform link clicks (Bandcamp, Spotify, YouTube, SoundCloud)
--     Covers: bandcamp_click, spotify_click, youtube_click, soundcloud_click_*
--     NOTE: playing a track/video inside an on-page embed (SoundCloud,
--     YouTube, or Spotify) fires the exact same event name + label as
--     clicking the equivalent outbound link, by design — this view (and
--     GA4 itself) cannot tell an embed play apart from a real link click.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `PROJECT_ID.DATASET_ID.v_music_link_clicks` AS
SELECT
  event_date,
  TIMESTAMP_MICROS(event_timestamp)                                      AS event_time,
  event_name,
  CASE
    WHEN event_name = 'bandcamp_click'             THEN 'Bandcamp'
    WHEN event_name = 'spotify_click'               THEN 'Spotify'
    WHEN event_name = 'youtube_click'               THEN 'YouTube'
    WHEN event_name LIKE 'soundcloud_click_%'       THEN 'SoundCloud'
  END                                                                    AS platform,
  CASE
    WHEN event_name LIKE 'soundcloud_click_%'
      THEN REPLACE(event_name, 'soundcloud_click_', '')
  END                                                                    AS artist_slug,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'event_label')      AS link_label,
  geo.country                                                            AS country,
  device.category                                                        AS device_category,
  user_pseudo_id
FROM `PROJECT_ID.DATASET_ID.events_*`
WHERE event_name IN ('bandcamp_click', 'spotify_click', 'youtube_click')
   OR event_name LIKE 'soundcloud_click_%';


-- ============================================================================
-- SUMMARY / KPI QUERIES
-- Use these directly in Looker Studio as "Custom Query" data sources,
-- or create additional views from them.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 7. Daily overview: event counts per day grouped by event type
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `PROJECT_ID.DATASET_ID.v_daily_overview` AS
SELECT
  event_date,
  CASE
    WHEN event_name LIKE 'file_download_%'      THEN 'Downloads'
    WHEN event_name LIKE 'social_click_%'       THEN 'Social Clicks'
    WHEN event_name LIKE 'dope_box_%'           THEN 'Dope Box'
    WHEN event_name = 'demo_play'               THEN 'Demo Plays'
    WHEN event_name IN ('acid_mode', 'background_change', 'embeds_hide')
                                                THEN 'UI Engagement'
    WHEN event_name IN ('bandcamp_click', 'spotify_click', 'youtube_click')
      OR event_name LIKE 'soundcloud_click_%'   THEN 'Music Link Clicks'
    ELSE 'Other'
  END                                                                    AS event_group,
  event_name,
  COUNT(*)                                                               AS event_count,
  COUNT(DISTINCT user_pseudo_id)                                         AS unique_users
FROM `PROJECT_ID.DATASET_ID.events_*`
WHERE event_name IN (
  'acid_mode', 'background_change', 'embeds_hide',
  'dope_box_open', 'dope_box_play', 'dope_box_stop',
  'demo_play', 'bandcamp_click', 'spotify_click', 'youtube_click'
)
OR event_name LIKE 'file_download_%'
OR event_name LIKE 'social_click_%'
OR event_name LIKE 'soundcloud_click_%'
GROUP BY event_date, event_group, event_name;


-- ----------------------------------------------------------------------------
-- 8. Download funnel: visitors → demo plays → downloads
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `PROJECT_ID.DATASET_ID.v_download_funnel` AS
SELECT
  event_date,
  COUNT(DISTINCT CASE WHEN event_name = 'page_view'  THEN user_pseudo_id END) AS visitors,
  COUNT(DISTINCT CASE WHEN event_name = 'demo_play'  THEN user_pseudo_id END) AS demo_listeners,
  COUNT(DISTINCT CASE WHEN event_name LIKE 'file_download_%'
                                                      THEN user_pseudo_id END) AS downloaders
FROM `PROJECT_ID.DATASET_ID.events_*`
GROUP BY event_date;
