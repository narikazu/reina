require 'octokit'

username     = ''
password     = ''
org_name     = 'honeypotio'
board_name   = 'The Agile Bear'
column_name  = 'Live/Done'
client = Octokit::Client.new(login: username, password: password)

user = client.user
abort 'Login error' if user.login != username

projects = client.org_projects(org_name)
project_id = projects.find { |pj| pj[:name] == board_name }[:id]

project = client.project_columns(project_id)
done_column_id = project.find { |c| c[:name] == column_name }[:id]

cards = []
i = 0
while (card = client.column_cards(done_column_id, page: i += 1)).size > 0
  cards.concat(card)
end

issue_cards = cards.select { |c| c[:content_url] }
issue_uris = issue_cards.map { |c| URI.parse(c[:content_url]) }
issue_uris.map! do |issue_uri|
  components = issue_uri.path.split('/') # ["", "repos", "org_project", "project_name", "issues", "1234"]
  repo = components[2..3].join('/')
  issue_id = components.last
  [repo, issue_id]
end

puts "Closing #{issue_uris.size}..."

issue_uris.each do |(repo, issue_id)|
  client.close_issue(repo, issue_id)
end
