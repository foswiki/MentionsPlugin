# ---+ Extensions
# ---++ MentionsPlugin
# This is the configuration used by the <b>MentionsPlugin</b>.

# **BOOLEAN**
$Foswiki::cfg{MentionsPlugin}{EmailNotification} = 1;

# **STRING 100 LABEL="Mode" **
# extract mentions from all, text, formfields, comments, or metadata. This is a comma separated list of ids.
$Foswiki::cfg{MentionsPlugin}{Mode} = "all";

# **BOOLEAN**
$Foswiki::cfg{MentionsPlugin}{Debug} = 0;

# **REGEX EXPERT**
# A regular expression of topics that should not be processed.
$Foswiki::cfg{MentionsPlugin}{ExcludeWeb} = '^(System|Applications([\./].*)?|(.*[\./])?Trash([\./].*)?)$';

# **REGEX EXPERT**
# A regular expression of topics that should not be processed.
$Foswiki::cfg{MentionsPlugin}{ExcludeTopic} = '^(WebAtom|WebRss|WebSearch.*|WebChanges|WebStatistics|WebNotify|WebTopicList|WebIndex|WebLeftBar|WebSideBar|WebPreferences|TrashAttachment|WebLeftBar.*)$';

# **REGEX EXPERT**
# A regular expression of WikiUsers that are not notified or don't trigger notifications
$Foswiki::cfg{MentionsPlugin}{ExcludeWikiUser} = '^(AdminUser|WikiGuest)$';

# **STRING*
# Format string to customize the mentions link to a user profile page
$Foswiki::cfg{MentionsPlugin}{MentionsFormat} = '<a href="%url%" class="mention %class%">%title%</a>';

1;
