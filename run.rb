require 'mechanize'
require 'aggregate'
require 'dotenv'
require 'pry'

Dotenv.load!

def fetch_env(key)
  ENV.fetch(key) { raise KeyError, "no ENV var called #{key.inspect}" }
end

username = fetch_env("MEMRISE_USERNAME")
password = fetch_env("MEMRISE_PASSWORD")
course_id = fetch_env("MEMRISE_COURSE_ID")

SECONDS = 1
MINUTES = 60 * SECONDS
HOURS = 60 * MINUTES
DAYS = 24 * HOURS

a = Mechanize.new { |agent|
  agent.user_agent_alias = 'Mac Safari'
}

login_url = 'http://www.memrise.com/login/'
course_url = "http://www.memrise.com/course/#{course_id}"

@things = []

class Thing
  def initialize(german, english, status)
    @german = german
    @english = english
    @status = status
    @time = parse_status(status)
  end
  attr_reader :german, :english, :status, :time

  def parse_status(status)
    case status
    when "Ignored", "to be learned"
      -1
    when "now"
      0
    when /\Ain ([\d\.]+) seconds\z/
      Float($1) * SECONDS
    when "in about a minute"
      1 * MINUTES
    when /\Ain (\d+) minutes\z/
      Integer($1) * MINUTES
    when "in about an hour"
      1 * HOURS
    when /\Ain (\d+) hours\z/
      Integer($1) * HOURS
    when "in about a day"
      1 * DAYS
    when /\Ain (\d+) days\z/
      Integer($1) * DAYS
    else
      raise "unknown status: #{status.inspect}"
    end
  end

  def stat_time
    @time + 1
  end
end

def handle(page)
  puts "handling #{page.title}"

  page.search(".things .thing").each do |thing|
    german = thing.at(".col_a div").text
    english = thing.at(".col_b div").text
    status = if status_el = thing.at(".status")
      status_el.text
    else
      "to be learned"
    end
    @things << Thing.new(german, english, status)
  end

  if link = page.select_links(".level-nav-next").first
    handle(link.click)
  end
end

a.get(login_url) do |page|
  form = page.form_with!(action: "/login/")
  form.username = username
  form.password = password
  page = form.submit
  raise "failed to login" unless page.at(".username").text == username
end

a.get(course_url) do |page|
  if link = page.select_links(".level").first
    unless link.node.at(".level-index").text == "1"
      raise "no first level link"
    end
  else
    raise "no links"
  end
  page = link.click
  handle(page)
end

grouped = @things.group_by(&:status).map {|status,things| [status, things.map(&:german)]}.sort_by {|status,things| status}
sorted = @things.sort_by(&:time).map {|thing| [thing.german, thing.time]}

stats = Aggregate.new
@things.each do |thing|
  stats << thing.stat_time
end

puts stats

binding.pry
