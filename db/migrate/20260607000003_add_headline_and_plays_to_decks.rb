class AddHeadlineAndPlaysToDecks < ActiveRecord::Migration[8.1]
  def change
    # Layperson-facing copy for the interactive matchup card:
    #   headline -> one plain sentence (what the deck does, why it is scary)
    #   plays    -> [{ "they" => "...", "you" => "..." }] their-move/your-answer pairs
    add_column :decks, :headline, :string
    add_column :decks, :plays, :jsonb, default: [], null: false
  end
end
