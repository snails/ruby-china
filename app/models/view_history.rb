# coding: utf-8
# 每日浏览详细
class ViewHistory
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::BaseModel

  belongs_to :user, inverse_of: :view_histories
  belongs_to :topic, inverse_of: :view_histories

  index user_id: 1
  index topic_id: 1

  delegate :title, to: :topic, prefix: true, allow_nil: true
  delegate :login, to: :user, prefix: true, allow_nil: true

  def self.per_page
    50
  end

end
