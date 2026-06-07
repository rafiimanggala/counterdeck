# Join row linking a counter recommendation to one of the cards it names, so a
# multi-card recommendation can show every card's art.
class CounterRecommendationCard < ApplicationRecord
  belongs_to :counter_recommendation
  belongs_to :card

  validates :card_id, uniqueness: { scope: :counter_recommendation_id }
end
