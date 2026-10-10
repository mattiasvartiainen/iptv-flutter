/// Columns read by `CatalogItemSummary.fromRow` from `items m JOIN groups g`.
const String catalogItemSummaryColumns =
    'm.id AS id, m.title AS title, m.sort_title AS sort_title, '
    'm.kind AS kind, g.id AS group_id, g.title AS group_title, m.logo_url AS logo_url, '
    'm.logo_url AS artwork_url, m.ord AS ord, '
    'm.episode_number AS episode_number';
