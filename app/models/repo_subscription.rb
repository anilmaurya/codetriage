class RepoSubscription < ActiveRecord::Base
  validate :repo_id, :uniqueness => {:scope => :user_id}
  belongs_to :repo
  belongs_to :user
  has_many   :issue_assignments

  has_many   :issues, :through => :issue_assignments

  def ready_for_next?
    return true if last_sent_at.blank?
    last_sent_at < 24.hours.ago
  end

  def wait?
    !ready_for_next?
  end

  def send_triage_email!
    Resque.enqueue(SendTriageEmail, self.id)
  end

  def self.queue_triage_emails!
    find_each(:conditions => ["last_sent_at is null or last_sent_at < ?", 23.hours.ago]) do |repo_sub|
      repo_sub.send_triage_email!
    end
  end

  def issue_for_triage!
    assigned_issue_ids = self.issues.map(&:id) + [-1]
    repo.issues.where(:state => 'open').where("id not in (?)", assigned_issue_ids).all.sample
  end

  def assign_issue!
    return false if wait?
    issue = issue_for_triage!
    issue_assignments.create(:issue_id => issue.id) unless issue.blank?
    return issue
  ensure
    self.update_attributes :last_sent_at => Time.now unless wait?
  end


  class SendTriageEmail
    @queue = :send_triage_email
    def self.perform(id)
      repo_sub = RepoSubscription.includes(:user, :repo).where(:id => id).first
      issue    = repo_sub.assign_issue!
      UserMailer.send_triage(:repo => repo_sub.repo, :user => repo_sub.user, :issue => issue).deliver
    end
  end

end