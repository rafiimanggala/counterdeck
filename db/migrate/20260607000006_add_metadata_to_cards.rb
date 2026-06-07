class AddMetadataToCards < ActiveRecord::Migration[8.1]
  # Document-style sidecar for relational Card rows: stores multi-source
  # reconciliation provenance and detected field conflicts, so the catalog can
  # show WHY a value was chosen instead of silently picking one and hiding the
  # divergence between sources.
  def change
    add_column :cards, :metadata, :jsonb, null: false, default: {}
    add_index :cards, :metadata, using: :gin
  end
end
