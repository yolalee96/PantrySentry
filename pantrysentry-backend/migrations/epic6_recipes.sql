-- =====================================================================
-- Epic 6 — Recipe suggestions. NON-DESTRUCTIVE: CREATE TABLE IF NOT
-- EXISTS only. Safe to run on the live database.
-- =====================================================================

-- Recipes generated for a household, cached so that opening details or
-- recording usage refers to the same recipe, and so the LLM isn't called
-- every time someone opens the page. Availability is NOT stored here —
-- it's recalculated against the current inventory on every request.
CREATE TABLE IF NOT EXISTS recipe_suggestion_sets (
  set_id          INT AUTO_INCREMENT PRIMARY KEY,
  team_id         INT NOT NULL,
  source          VARCHAR(20) NOT NULL,          -- 'llm' now; 'dataset' later
  input_item_ids  JSON NOT NULL,                 -- inventory items offered to the source
  recipes_json    JSON NOT NULL,                 -- validated recipes (see util/recipe_matching.js)
  created_by      INT NOT NULL,
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_recipe_sets_team_created (team_id, created_at),
  CONSTRAINT fk_recipe_sets_team FOREIGN KEY (team_id) REFERENCES teams (team_id)
);

-- AC 6.3.7 — one row per "Update ingredients used" submission. The app
-- generates submission_id once per review; a retry with the same id is
-- answered from result_json instead of deducting again.
CREATE TABLE IF NOT EXISTS recipe_usage_submissions (
  submission_id   VARCHAR(64) PRIMARY KEY,
  team_id         INT NOT NULL,
  user_id         INT NOT NULL,
  recipe_id       VARCHAR(40) NULL,
  recipe_title    VARCHAR(200) NOT NULL,
  result_json     JSON NULL,
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_recipe_usage_team FOREIGN KEY (team_id) REFERENCES teams (team_id)
);
