# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
#
# MentionsPlugin is Copyright (C) 2021-2025 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::MentionsPlugin::Schema::MariaDB;

use strict;
use warnings;

use Foswiki::Plugins::MentionsPlugin::Schema;
our @ISA = ('Foswiki::Plugins::MentionsPlugin::Schema');

sub getDefinition {
  return [[
    "CREATE TABLE IF NOT EXISTS %prefix%mentions (
            date INTEGER,
            wikiName VARCHAR(255) NOT NULL,
            mentionedBy VARCHAR(255) NOT NULL,
            web VARCHAR(255) NOT NULL,
            topic VARCHAR(255) NOT NULL,
            times INTEGER DEFAULT 1
    ) DEFAULT CHARSET=utf8 DEFAULT COLLATE utf8_bin",

    "CREATE UNIQUE INDEX IF NOT EXISTS %prefix%idx_unique_mentions ON %prefix%mentions (wikiName, mentionedBy, web, topic)",
    "CREATE INDEX IF NOT EXISTS %prefix%idx_wikiName ON %prefix%mentions (wikiName)",
    "CREATE INDEX IF NOT EXISTS %prefix%idx_date ON %prefix%mentions (date)",
    "CREATE INDEX IF NOT EXISTS %prefix%idx_where ON %prefix%mentions (web, topic)",
  ], [
    "DROP INDEX %prefix%idx_unique_mentions ON %prefix%mentions",
    "ALTER TABLE %prefix%mentions ADD column part VARCHAR(255) NOT NULL",
  ], [
    "ALTER TABLE %prefix%mentions ADD column fingerPrint VARCHAR(255) NOT NULL",
    "ALTER TABLE %prefix%mentions DROP column times",
  ], [
    "ALTER TABLE %prefix%mentions CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_bin",
  ]];
}

1;
