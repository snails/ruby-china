# coding: utf-8
class RepliesController < ApplicationController
  load_and_authorize_resource :reply

  before_filter :find_topic

  def create
    @reply = Reply.new(reply_params)
    @reply.topic_id = @topic.id
    @reply.user_id = current_user.id

    if @reply.save
      current_user.read_topic(@topic)
      @msg = t('topics.reply_success')
      #处理浏览记录
      current_hour = Time.now.strftime('%Y%m%d%H') #2015010420
      current_date = Time.now.strftime('%Y%m%d') #20150104
      rp_hash_hour = Redis::HashKey.new("topics:replies:#{current_hour}", expiration: 24.hours)
      rp_hash_hour.incr(@topic.id)
      rp_hash_hour.set_expiration
      rp_hash_date = Redis::HashKey.new("topics:replies:#{current_date}", expiration: 7.days)
      rp_hash_date.incr(@topic.id)
      rp_hash_date.set_expiration

    else
      @msg = @reply.errors.full_messages.join('<br />')
    end
  end

  def edit
    @reply = Reply.find(params[:id])
  end

  def update
    @reply = Reply.find(params[:id])

    if @reply.update_attributes(reply_params)
      redirect_to(topic_path(@reply.topic_id), notice: '回帖更新成功。')
    else
      render action: 'edit'
    end
  end

  def destroy
    @reply = Reply.find(params[:id])
    if @reply.destroy
      #处理浏览记录
      current_hour = Time.now.strftime('%Y%m%d%H') #2015010420
      current_date = Time.now.strftime('%Y%m%d') #20150104
      rp_hash_hour = Redis::HashKey.new("topics:replies:#{current_hour}", expiration: 24.hours)
      rp_hash_hour.decr(@topic.id) if rp_hash_hour[@topic_id]
      rp_hash_date = Redis::HashKey.new("topics:replies:#{current_date}", expiration: 7.days)
      rp_hash_date.decr(@topic.id) if rp_hash_date[@topic_id]

      redirect_to(topic_path(@reply.topic_id), notice: '回帖删除成功。')
    else
      redirect_to(topic_path(@reply.topic_id), alert: '程序异常，删除失败。')
    end
  end

  protected

  def find_topic
    @topic = Topic.find(params[:topic_id])
  end

  def reply_params
    params.require(:reply).permit(:body)
  end
end
