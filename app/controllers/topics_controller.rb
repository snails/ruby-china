# coding: utf-8
require 'will_paginate/array'
class TopicsController < ApplicationController
  load_and_authorize_resource only: [:new, :edit, :create, :update, :destroy,
                                     :favorite, :unfavorite, :follow, :unfollow, :suggest, :unsuggest]
  caches_action :feed, :node_feed, :week_popular, expires_in: 1.hours
  caches_action :diary_popular, expires_in: 10.minutes

  def index
    @suggest_topics = Topic.without_hide_nodes.suggest.limit(3)
    suggest_topic_ids = @suggest_topics.map(&:id)

    @topics = Topic.last_actived.without_hide_nodes.where(:_id.nin => suggest_topic_ids)
    @topics = @topics.fields_for_list.includes(:user)
    @topics = @topics.paginate(page: params[:page], per_page: 15, total_entries: 1500)

    set_seo_meta t("menu.topics"), "#{Setting.app_name}#{t("menu.topics")}"
  end

  def feed
    @topics = Topic.recent.without_body.limit(20).includes(:node, :user, :last_reply_user)
    render layout: false
  end

  def node
    @node = Node.find(params[:id])
    @topics = @node.topics.last_actived.fields_for_list
    @topics = @topics.includes(:user).paginate(page: params[:page], per_page: 15)
    title = @node.jobs? ? @node.name : "#{@node.name} &raquo; #{t("menu.topics")}"
    set_seo_meta title, "#{Setting.app_name}#{t("menu.topics")}#{@node.name}", @node.summary
    render action: 'index'
  end

  def node_feed
    @node = Node.find(params[:id])
    @topics = @node.topics.recent.without_body.limit(20)
    render layout: false
  end

  %W(no_reply popular).each do |name|
    define_method(name) do
      @topics = Topic.send(name.to_sym).last_actived.fields_for_list.includes(:user)
      @topics = @topics.paginate(page: params[:page], per_page: 15, total_entries: 1500)

      set_seo_meta [t("topics.topic_list.#{name}"), t('menu.topics')].join(' &raquo; ')
      render action: 'index'
    end
  end

  def week_popular
    @topics = Topic.week_popular
    @topics = @topics.paginate(page: params[:page], per_page: 100, total_entries: 100)

    set_seo_meta [t("topics.topic_list.week_popular"), t('menu.topics')].join(' &raquo; ')
    render action: 'index'
  end

  def diary_popular
    @topics = Topic.diary_popular
    @topics = @topics.paginate(page: params[:page], per_page: 100, total_entries: 100)

    set_seo_meta [t("topics.topic_list.diary_popular"), t('menu.topics')].join(' &raquo; ')
    render action: 'index'
  end

  def recent
    @topics = Topic.recent.fields_for_list.includes(:user)
    @topics = @topics.paginate(page: params[:page], per_page: 15, total_entries: 1500)
    set_seo_meta [t('topics.topic_list.recent'), t('menu.topics')].join(' &raquo; ')
    render action: 'index'
  end

  def excellent
    @topics = Topic.excellent.recent.fields_for_list.includes(:user)
    @topics = @topics.paginate(page: params[:page], per_page: 15, total_entries: 1500)

    set_seo_meta [t('topics.topic_list.excellent'), t('menu.topics')].join(' &raquo; ')
    render action: 'index'
  end

  def show
    @topic = Topic.without_body.find(params[:id])
    @topic.hits.incr(1)
    user_id = current_user.try(:_id) || -1
    @node = @topic.node
    @show_raw = params[:raw] == '1'

    #处理浏览记录
    current_hour = Time.now.strftime('%Y%m%d%H') #2015010420
    current_date = Time.now.strftime('%Y%m%d') #20150104
    vh_hash_hour = Redis::HashKey.new("topics:vh:#{current_hour}", expiration: 24.hours)
    vh_hash_hour.incr(@topic.id)
    vh_hash_date = Redis::HashKey.new("topics:vh:#{current_date}", expiration: 7.days)
    vh_hash_date.incr(@topic.id)

    @per_page = Reply.per_page
    # 默认最后一页
    params[:page] = @topic.last_page_with_per_page(@per_page) if params[:page].blank?
    @page = params[:page].to_i > 0 ? params[:page].to_i : 1

    @replies = @topic.replies.unscoped.without_body.asc(:_id)
    @replies = @replies.paginate(page: @page, per_page: @per_page)
    
    check_current_user_status_for_topic
    set_special_node_active_menu
    
    set_seo_meta "#{@topic.title} &raquo; #{t("menu.topics")}"

    fresh_when(etag: [@topic, @has_followed, @has_favorited, @replies, @node, @show_raw])
  end
  
  def check_current_user_status_for_topic
    return false if not current_user
    
    # 找出用户 like 过的 Reply，给 JS 处理 like 功能的状态
    @user_liked_reply_ids = []
    @replies.each { |r| @user_liked_reply_ids << r.id if r.liked_user_ids.index(current_user.id) != nil }
    # 通知处理
    current_user.read_topic(@topic)
    # 是否关注过
    @has_followed = @topic.follower_ids.index(current_user.id) == nil
    # 是否收藏
    @has_favorited = current_user.favorite_topic_ids.index(@topic.id) == nil
  end
  
  def set_special_node_active_menu
    case @node.try(:id)
    when Node.jobs_id
      @current = ["/jobs"]
    end
  end

  def new
    @topic = Topic.new
    if !params[:node].blank?
      @topic.node_id = params[:node]
      @node = Node.find_by_id(params[:node])
      render_404 if @node.blank?
    end

    set_seo_meta "#{t('topics.post_topic')} &raquo; #{t('menu.topics')}"
  end

  def edit
    @topic = Topic.find(params[:id])
    @node = @topic.node

    set_seo_meta "#{t('topics.edit_topic')} &raquo; #{t('menu.topics')}"
  end

  def create
    @topic = Topic.new(topic_params)
    @topic.user_id = current_user.id
    @topic.node_id = params[:node] || topic_params[:node_id]

    if @topic.save
      redirect_to(topic_path(@topic.id), notice: t('topics.create_topic_success'))
    else
      render action: 'new'
    end
  end

  def preview
    @body = params[:body]

    respond_to do |format|
      format.json
    end
  end

  def update
    @topic = Topic.find(params[:id])
    if @topic.lock_node == false || current_user.admin?
      # 锁定接点的时候，只有管理员可以修改节点
      @topic.node_id = topic_params[:node_id]

      if current_user.admin? && @topic.node_id_changed?
        # 当管理员修改节点的时候，锁定节点
        @topic.lock_node = true
      end
    end
    @topic.title = topic_params[:title]
    @topic.body = topic_params[:body]

    if @topic.save
      redirect_to(topic_path(@topic.id), notice: t('topics.update_topic_success'))
    else
      render action: 'edit'
    end
  end

  #如果某个 topic 被删除，则清空对应 topic_id 的所有记录
  def remove_topic_vhs_and_repies(topic_id)
    0.upto(23) do |index|
      current_hour = (Time.now - index.hours).strftime('%Y%m%d%H')
      current_date = (Time.now - index.days).strftime('%Y%m%d')

      vh_hash_hour = Redis::HashKey.new("topics:vh:#{current_hour}", expiration: 24.hours)
      vh_hash_hour.delete(topic_id)
      rp_hash_hour = Redis::HashKey.new("topics:replies:#{current_hour}", expiration: 24.hours)
      rp_hash_hour.delete(topic_id)
      #只处理7天的数据
      if(index < 7)
        vh_hash_date = Redis::HashKey.new("topics:vh:#{current_date}", expiration: 7.days)
        vh_hash_date.delete(topic_id)
        rp_hash_date = Redis::HashKey.new("topics:replies:#{current_date}", expiration: 7.days)
        rp_hash_date.delete(topic_id)
      end
    end
  end

  def destroy
    @topic = Topic.find(params[:id])
    result = @topic.destroy_by(current_user)
    remove_topic_vhs_and_repies(@topic_id) if result #删除成功后，清除 redis 缓存数据
    redirect_to(topics_path, notice: t('topics.delete_topic_success'))
  end

  def favorite
    current_user.favorite_topic(params[:id])
    render text: '1'
  end

  def unfavorite
    current_user.unfavorite_topic(params[:id])
    render text: '1'
  end

  def follow
    @topic = Topic.find(params[:id])
    @topic.push_follower(current_user.id)
    render text: '1'
  end

  def unfollow
    @topic = Topic.find(params[:id])
    @topic.pull_follower(current_user.id)
    render text: '1'
  end

  def suggest
    @topic = Topic.find(params[:id])
    @topic.update_attributes(excellent: 1)
    redirect_to @topic, success: '加精成功。'
  end

  def unsuggest
    @topic = Topic.find(params[:id])
    @topic.update_attribute(:excellent, 0)
    redirect_to @topic, success: '加精已经取消。'
  end

  private

  def topic_params
    params.require(:topic).permit(:title, :body, :node_id)
  end
end
