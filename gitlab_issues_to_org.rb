# frozen_string_literal: true

require 'bundler/inline'
require 'date'
require 'delegate'
require 'erb'

gemfile do
  source 'https://rubygems.org'
  gem 'gitlab'
  gem 'redcarpet'
  gem 'awesome_print'
end

require 'redcarpet/render_strip'

OUTPUT_FILE = ENV.fetch('GITLAB_TO_ORG_OUTPUT')
PROJECT_IDS = ENV.fetch('GITLAB_TO_ORG_PROJECT_IDS')
API_URL = ENV.fetch('GITLAB_TO_ORG_API_URL')
API_TOKEN = ENV.fetch('GITLAB_TO_ORG_API_TOKEN')
SELF_USER = ENV.fetch('GITLAB_SELF_USER')

Gitlab.configure do |config|
  config.endpoint       = API_URL
  config.private_token  = API_TOKEN
end

class GitlabIssue < SimpleDelegator
  def headline
    "#{org_state} #{title} (##{id})"
  end

  def assigned_to_me?
    !assignee.nil? && assignee['username'] == SELF_USER
  end

  # id within the project ticket tracker
  def id
    iid
  end

  # global id
  def uid
    id
  end

  def ref
    references['full']
  end

  def plain_description
    return '' unless description

    @plain_description ||= Redcarpet::Markdown.new(Redcarpet::Render::StripDown).render(description)
  end

  def assigned_user
    !assignee.nil? && assignee['name']
  end

  def org_link
    "[[#{web_url}][#{title}]]"
  end

  def tags
    labels.map(&:downcase)
  end

  def scheduled_for
    return nil if due_date.nil?

    d = Date.strptime(due_date, '%Y-%m-%d')
    d.strftime('<%Y-%m-%d %a>')
  end

  def org_state
    if state == 'closed'
      'DONE'
    elsif state == 'opened' && assigned_to_me?
      'TODO'
    elsif state == 'opened' && !assigned_to_me?
      'WAIT'
    else
      raise "Unknown ticket state: #{state}"
    end
  end
end

class OrgFile
  attr_reader :issues

  def initialize(issues)
    @issues = issues.sort_by { |issue| -issue.uid }
  end

  def save
    content = ERB.new(DATA.read).result(binding)
    File.write(OUTPUT_FILE, content)
  end
end

issues = PROJECT_IDS.split(',').flat_map do |project_id|
  Gitlab
    .issues(project_id, { per_page: 50, state: 'opened' })
    .auto_paginate.map { |issue| GitlabIssue.new(issue) }
end

org_file = OrgFile.new(issues)

org_file.save

puts "Success! #{org_file.issues.count} issues were written to #{OUTPUT_FILE}"

__END__
# -*- buffer-read-only: t -*-
#+TITLE: GitLab Issues Export
#+CATEGORY: Tickets
#+SETUPFILE: /Users/fabrik42/org/_ioki_config.org
#+STARTUP: showall
#+EXPORT_DATE: <%= Time.now.iso8601 %>

<% issues.each do |issue| %>
* <%= issue.headline %>
<% if issue.scheduled_for %>SCHEDULED: <%= issue.scheduled_for %>
<% end %><%= issue.org_link %>

<%= issue.ref %>

<% if issue.assigned_user %>Assigned: <%= issue.assigned_user %><% end %>
<% if issue.plain_description %><%= issue.plain_description %><% end %><% end %>
