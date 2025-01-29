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

package Foswiki::Plugins::MentionsPlugin::Schema::SQLite;

use strict;
use warnings;

use Foswiki::Plugins::MentionsPlugin::Schema;
our @ISA = ('Foswiki::Plugins::MentionsPlugin::Schema');

sub getDefinition {
  return [[
    "CREATE TABLE IF NOT EXISTS %prefix%mentions (
            date INTEGER,
            wikiName TEXT NOT NULL,
            mentionedBy TEXT NOT NULL,
            web TEXT NOT NULL,
            topic TEXT NOT NULL,
            times INTEGER DEFAULT 1
    )",

    "CREATE UNIQUE INDEX IF NOT EXISTS %prefix%idx_unique_mentions ON %prefix%mentions (wikiName, mentionedBy, web, topic)",
    "CREATE INDEX IF NOT EXISTS %prefix%idx_wikiName ON %prefix%mentions (wikiName)",
    "CREATE INDEX IF NOT EXISTS %prefix%idx_date ON %prefix%mentions (date)",
    "CREATE INDEX IF NOT EXISTS %prefix%idx_where ON %prefix%mentions (web, topic)",
  ], [
    "DROP INDEX IF EXISTS %prefix%idx_unique_mentions",
    "ALTER TABLE %prefix%mentions ADD part TEXT",
  ], [
    "ALTER TABLE %prefix%mentions ADD column fingerPrint TEXT",
    "ALTER TABLE %prefix%mentions DROP column times",
  ]];
};

1;
