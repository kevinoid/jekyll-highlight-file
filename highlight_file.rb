# A Liquid filter for Jekyll which outputs highlighted file content
#
# It is licensed under the terms of the MIT License.
# The complete text of the license is available in the project documentation.
#
# Copyright 2012 Kevin Locke <kevin@kevinlocke.name>

require 'i18n'

module Jekyll
  class HighlightFileBlock < Liquid::Tag

    DEFAULT_OPTIONS = {
      # Use the GitHub Gist JavaScript to render gists
      :gist_script      => 'false',
      # Add markup with links to the git host (if recognized)
      :git_host_footer  => 'true',
      # Pull the git repository before rendering
      :pull             => 'false',
      # Location where local clones are stored
      :repos_dir        => '_highlight_repos',
    }

    # Common option syntax
    OPTION_SYNTAX = /([^="\s]+)(?:=([^"\s]+|"(?:[^\\"]*|\\.)*"))?/

    OPTION_TRUE = /\A(?:1|on|true|y|yes)\z/i

    # highlight_file argument syntax "<lang> <file> [opt[=val]]*"
    FILE_SYNTAX = /\A\s*([^"\s]+|"(?:[^\\"]*|\\.)*")          # Language
      \s+([^"\s]+|"(?:[^\\"]*|\\.)*")                         # File
      ((?:\s+[^="\s]+(?:=(?:[^"\s]+|"(?:[^\\"]*|\\.)*"))?)*)  # Options
      \s*\Z/x

    # highlight_git argument syntax "<lang> <repo> <file> [opt[=val]]*"
    GIT_SYNTAX = /\A\s*([^"\s]+|"(?:[^\\"]*|\\.)*")           # Language
      \s+([^"\s]+|"(?:[^\\"]*|\\.)*")                         # URL|path
      \s+([^"\s]+|"(?:[^\\"]*|\\.)*")                         # File
      ((?:\s+[^="\s]+(?:=(?:[^"\s]+|"(?:[^\\"]*|\\.)*"))?)*)  # Options
      \s*\z/x

    # highlight_gist argument syntax "<lang> <gist user> <gist id> <file> [opt[=val]]*"
    GIST_SYNTAX = /\A\s*([^"\s]+|"(?:[^\\"]*|\\.)*")          # Language
      \s+([^"\s]+|"(?:[^\\"]*|\\.)*")                         # Gist User
      \s+([^"\s]+|"(?:[^\\"]*|\\.)*")                         # Gist ID
      \s+([^"\s]+|"(?:[^\\"]*|\\.)*")                         # File
      ((?:\s+[^="\s]+(?:=(?:[^"\s]+|"(?:[^\\"]*|\\.)*"))?)*)  # Options
      \s*\z/x

    HostInfo = Struct.new(:repo_url, :file_url, :file_raw_url, :site_name, :site_url)

    def initialize(tag_name, text, token)
      super

      case tag_name
      when 'highlight_file'
        if parts = text.match(FILE_SYNTAX)
          @language     = unquote parts[1]
          @filename     = unquote parts[2]
          options_str   = parts[3]

          @options      = parse_options options_str
        else
          raise SyntaxError, "Unrecognized argument '#{text}'.\n" +
            "Usage: #{tag_name} <lang> <file> [option[=val]]*"
        end
      when 'highlight_git'
        if parts = text.match(GIT_SYNTAX)
          @language     = unquote parts[1]
          @repo_url     = unquote parts[2]
          @filename     = unquote parts[3]
          options_str   = parts[4]

          @options      = parse_options options_str
          @local_dir    = local_dir_for_repo @repo_url
        else
          raise SyntaxError, "Unrecognized argument '#{text}'.\n" +
            "Usage: #{tag_name} <lang> <repo> <file> [option[=val]]*"
        end
      when 'highlight_gist'
        if parts = text.match(GIST_SYNTAX)
          @language     = unquote parts[1]
          @gist_user    = unquote parts[2]
          @gist_id      = unquote parts[3]
          @repo_url     = git_url_for_gist @gist_id
          @filename     = unquote parts[4]
          options_str   = parts[5]

          @options      = parse_options options_str
          @local_dir    = local_dir_for_repo @repo_url
        else
          raise SyntaxError, "Unrecognized argument '#{text}'.\n" +
            "Usage: #{tag_name} <lang> <gist> <file> [option[=val]]*"
        end
      else
        raise "Unrecognized tag name '#{tag_name}'"
      end
    end

    def parse_options(options_str)
      options = DEFAULT_OPTIONS.clone
      @highlight_options = {}
      options_str.scan(OPTION_SYNTAX) { |optparts|
        optname = optparts[0].to_sym
        optval = optparts[1] ? unquote(optparts[1]) : 'true'

        if options.has_key? optname
          options[optname] = optval
        else
          @highlight_options[optparts[0]] = optparts[1]
        end
      }

      options
    end

    def render(context)
      content     = get_content
      highlighted = highlight content, context
      footer      = make_footer

      if @options[:gist_script] =~ OPTION_TRUE and @gist_id
        script_url = script_url_for_gist @gist_user, @gist_id, @filename
        # Note:  Space in <script> and \n after </script> needed for Maruku
        body = <<-BODY
<script type="text/javascript" src="#{script_url}"> </script>
<noscript>
#{highlighted}#{footer}
</noscript>
BODY
      else
        body = highlighted + footer
      end

      %Q{\n<div class="highlight-file">\n#{body}\n</div>\n}
    end

    def get_content
      if @repo_url and not File.directory? @local_dir
        clone_repo @repo_url, @local_dir
      elsif @repo_url and @options[:pull] =~ OPTION_TRUE
        pull_repo @local_dir
      end

      if @local_dir
        file_path = File.join @local_dir, *@filename.split('/')
      else
        file_path = File.join *@filename.split('/')
      end

      File.read file_path
    end

    def highlight(content, context)
      options_str = @highlight_options.to_a.map { |opt|
        opt[1] ? opt.join('=') : opt[0]
      }.join ' '

      highlight_block = Jekyll::Tags::HighlightBlock.new(
        'highlight',
        @language + (options_str.empty? ? '' : ' ' + options_str),
        [ content, "{% endhighlight %}" ]
      )

      highlight_block.render context
    end

    def make_footer
      return if not @options[:git_host_footer]

      if host_info = get_host_info
<<-FOOTER
<div class="highlight-git-host-footer">
  <span class="highlight-git-repo-host">
    <a href="#{host_info.repo_url}">This repository</a> is available on
    <a href="#{host_info.site_url}">#{host_info.site_name}</a>.
  </span>
  <span class="highlight-git-file-raw">
    <span>View #{@filename}:</span>
    <a href="#{host_info.file_url}">Pretty</a>
    <a href="#{host_info.file_raw_url}">Raw</a>
  </span>
</div>
FOOTER
      else
        ""
      end
    end

    def git_url_for_gist(gist_id)
      "git://gist.github.com/#{gist_id}.git"
    end

    def get_host_info
      if @gist_id
        HostInfo.new(
          "https://gist.github.com/#{@gist_user}/#{@gist_id}",
          "https://gist.github.com/#{@gist_user}/#{@gist_id}##{filename_to_gist_id @filename}",
          "https://gist.github.com/#{@gist_user}/#{@gist_id}/raw/#{@filename}",
          'GitHub',
          'https://github.com'
        )
      elsif %r{^(?:(?:git|https)://|git@)github\.com/(.*)\.git$} =~ @repo_url
        HostInfo.new(
          "https://github.com/#{$1}",
          "https://github.com/#{$1}/blob/master/#{@filename}",
          "https://github.com/#{$1}/raw/master/#{@filename}",
          'GitHub',
          'https://github.com'
        )
      end
    end

    def local_dir_for_repo(repo_url)
      if File.directory? repo_url
        repo_url
      else
        dir_name = repo_url.sub(/\A\w+:\/\//, '')
          .sub(/\.git$/, '')
          .gsub(/[<>:"\/\\|?*\0-\31]+/, '-')
        File.join @options[:repos_dir], dir_name
      end
    end

    def script_url_for_gist(gist_user, gist_id, filename)
      script_url = "https://gist.github.com/#{gist_user}/#{gist_id}.js"
      script_url += "?file=#{filename}" if filename
    end

    def clone_repo(repo_url, local_dir)
      system 'git', 'clone', repo_url, local_dir \
        or raise 'Error cloning repository'
    end

    def pull_repo(local_dir)
      Dir.chdir(local_dir) {
        system 'git', 'pull' \
          or raise 'Error pulling repository'
      }
    end

    # Convert a filename to the fragment id used for the file on a GitHub
    # gist page.
    def filename_to_gist_id(filename)
      # Use old default to avoid warning if not configured
      I18n.enforce_available_locales = false if I18n.enforce_available_locales.nil?
      'file-' +
        I18n.transliterate(filename)
          .gsub(/[^A-Za-z0-9_]+/, '-')
          .downcase
    end

    # If the argument string is a quoted string, remove quotes and unescape
    def unquote(string)
      if string.length > 1 and string.start_with? '"' and string.end_with? '"'
        string[1..-2].gsub(/\\(.)/, '\1')
      else
        string
      end
    end

    # Escape any characters which are invalid in HTML or XHTML
    def escape_xhtml(text)
      # Note: > does not need to be escaped in XML content, but HTML4 spec
      # says "should escape" to avoid problems with older user agents
      # Note: Characters with restricted/discouraged usage are left unchanged
      text.gsub(/[&<>]|[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD\u10000-\u10FFF]/) do | match |
        case match
        when '&' then '&amp;'
        when '<' then '&lt;'
        when '>' then '&gt;'
        else "&#x#{match.ord};"
        end
      end
    end

    # Remove or escape any characters which are invalid in an attribute in
    # HTML or XHTML
    def escape_xhtml_attr(text)
      # Note: Characters with restricted/discouraged usage are left unchanged
      text.gsub(/[&<>'"]|[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD\u10000-\u10FFF]/) do | match |
        case match
        when '&' then '&amp;'
        when '<' then '&lt;'
        when '>' then '&gt;'
        when "'" then '&apos;'
        when '"' then '&quote;'
        else "&#x#{match.ord};"
        end
      end
    end
  end
end

Liquid::Template.register_tag('highlight_file', Jekyll::HighlightFileBlock)
Liquid::Template.register_tag('highlight_git', Jekyll::HighlightFileBlock)
Liquid::Template.register_tag('highlight_gist', Jekyll::HighlightFileBlock)
