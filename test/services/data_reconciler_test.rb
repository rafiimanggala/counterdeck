require "test_helper"

class DataReconcilerTest < ActiveSupport::TestCase
  KEY = 9_000_100

  def ygo_row(overrides = {})
    {
      "id" => KEY, "name" => "Maxx \"C\"", "type" => "Effect Monster",
      "attribute" => "EARTH", "race" => "Insect", "atk" => 500, "def" => 200,
      "level" => 2, "archetype" => nil, "desc" => "Quick draw engine stopper."
    }.merge(overrides)
  end

  def manual(attributes)
    DataReconciler::HashAdapter.new(source: "manual", priority: 100,
                                    rows: [{ natural_key: KEY, attributes: attributes }])
  end

  test "agreeing sources produce no conflict" do
    sources = [DataReconciler::YgoprodeckAdapter.new([ygo_row], priority: 50), manual("atk" => 500)]
    res = DataReconciler.new(sources: sources).reconcile[KEY]
    assert_empty res[:conflicts]
    assert_equal 500, res[:attributes]["atk"]
  end

  test "higher-priority source wins a conflict and the divergence is recorded" do
    sources = [DataReconciler::YgoprodeckAdapter.new([ygo_row("atk" => 500)], priority: 50), manual("atk" => 600)]
    res = DataReconciler.new(sources: sources).reconcile[KEY]

    assert_equal 600, res[:attributes]["atk"]
    assert_equal "manual", res[:provenance]["atk"]
    conflict = res[:conflicts].find { |c| c[:field] == "atk" }
    assert_equal 600, conflict[:chosen]
    assert_equal "manual", conflict[:chosen_source]
    assert_equal "ygoprodeck", conflict[:losing_source]
  end

  test "falls back to a lower-priority source when the winner's field is nil" do
    sources = [manual("atk" => nil, "name" => "Maxx C"),
               DataReconciler::YgoprodeckAdapter.new([ygo_row("atk" => 500)], priority: 50)]
    res = DataReconciler.new(sources: sources).reconcile[KEY]

    assert_equal 500, res[:attributes]["atk"]
    assert_equal "ygoprodeck", res[:provenance]["atk"]
  end

  test "apply! upserts a card, stores provenance and conflicts, and is idempotent" do
    sources = [DataReconciler::YgoprodeckAdapter.new([ygo_row("atk" => 500)], priority: 50), manual("atk" => 600)]

    result = nil
    assert_difference "Card.count", 1 do
      result = DataReconciler.new(sources: sources).apply!
    end
    assert_equal 1, result.cards_upserted
    assert_equal 1, result.conflicts

    card = Card.find_by(ygo_id: KEY)
    assert_equal 600, card.atk
    assert_includes card.reconciled_sources, "manual"
    assert_equal "atk", card.data_conflicts.first["field"]

    assert_no_difference "Card.count" do
      DataReconciler.new(sources: sources).apply!
    end
  end

  test "a failing source is skipped without aborting the run" do
    broken = Object.new
    def broken.records = raise("boom")
    sources = [broken, DataReconciler::YgoprodeckAdapter.new([ygo_row], priority: 50)]

    assert_difference "Card.count", 1 do
      DataReconciler.new(sources: sources, logger: Logger.new(nil)).apply!
    end
  end
end
