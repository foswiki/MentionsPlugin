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

package Foswiki::Plugins::MentionsPlugin::Schema;

use strict;
use warnings;

use Foswiki::DBI::Schema;
our @ISA = ('Foswiki::DBI::Schema');

sub getType {
  return "MentionsPlugin";
}

1;
