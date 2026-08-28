# frozen_string_literal: true

# redmine_mcp_plugin - a Model Context Protocol server that runs inside Redmine
# Copyright (C) 2026  Joao Figueira
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

Redmine::Plugin.register :redmine_mcp_plugin do
  name        'Redmine MCP Server'
  author      'Joao Figueira'
  description 'Exposes Redmine over the Model Context Protocol, in-process, ' \
              'using Redmine\'s own authentication and permission system.'
  version     RedmineMcpPlugin::VERSION
  url         'https://github.com/joaoperfig/redmine_mcp_plugin'
  author_url  'https://github.com/joaoperfig'

  # Redmine 6.1 is the floor for OAuth2 (Doorkeeper) support, which is the
  # authentication mode this plugin is built around. Everything else it uses
  # -- User#allowed_to?, the .visible scopes -- is much older.
  requires_redmine version_or_higher: '6.1.0'

  settings default: RedmineMcpPlugin::Settings::DEFAULTS,
           partial: 'settings/redmine_mcp_plugin_settings'
end
