highlight\_file Liquid Filter for Jekyll
=======================================

highlight\_file is a plugin for Jekyll which provides a Liquid filter for
displaying highlighted code from a file (possibly in a local or remote git
repository).  In particular, it makes including GitHub gists simple and
painless.

First, some quick examples.  To highlight a file from the local filesystem:

    {% highlight_file java /home/me/code/example.java %}

To include a file in a git repository:

    {% highlight_git c git://git.xfce.org/apps/terminal terminal/terminal-dialogs.c %}

Or to include a gist:

    {% highlight_gist ruby 3131752 content-with-post.rb linenos=table %}

Each of the arguments can be either a word or a quoted string (double-quoted
string which allows backslash to escape characters).  Additionally, each tag
supports a set of options specified as either `key` or `key=value` pairs
(where values may be quoted strings).  The supported options are listed below.

Supported Options
=================

The supported options are:

gist\_script
: Use the GitHub Gist JavaScript to render gists.  Built-in highlighting is
  provided in a &lt;noscript&gt; tag following the GitHub script. (default: false)

git\_host\_footer
: Add markup with links to the git host (if recognized) following the
  highlighted code. (default: true)

pull
: Pull the git repository before rendering to ensure that it is up-to-date.
  (default: false)

repos\_dir
: Location where local clones of the git repositories are stored.
  (default: `_highlight_repos`)

Additionally, any options which are not recognized are passed through to the
built-in `highlight` tag.  This allows the user to specify any option
supported by `highlight`.

Additional Information
======================

Installation instructions are available in `INSTALL.txt`.
Major changes are listed in `ChangeLog.txt`.
Complete license text is available in `COPYING.txt`.
