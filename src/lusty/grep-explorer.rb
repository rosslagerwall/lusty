# Copyright (C) 2007-2010 Stephen Bach
#
# Permission is hereby granted to use and distribute this code, with or without
# modifications, provided that this copyright notice is copied with it. Like
# anything else that's free, this file is provided *as is* and comes with no
# warranty of any kind, either expressed or implied. In no event will the
# copyright holder be liable for any damages resulting from the use of this
# software.

# STEVE TODO:
# - save grep entries and selection on cleanup and restore at next launch
#   - so not have to retype everything to see next entry
# - show context
# - some way for user to indicate case-sensitive regex
module Lusty
class GrepExplorer < Explorer
  public
    def initialize
      super
      @prompt = Prompt.new
      @buffer_entries = []
      @matched_strings = []
    end

    def run
      unless @running
        @prompt.clear!
        @curbuf_at_start = VIM::Buffer.current
        @buffer_entries = compute_buffer_entries()
        super
      end
    end

  private
    def title
      '[LustyExplorer-GrepBufferContents]'
    end

    # STEVE also highlight name:##: part somewhere
    # STEVE regular "dir/" highlighting should not apply
    def on_refresh
      if VIM::has_syntax?

      '\%(^\|' + @@COLUMN_SEPARATOR + '\)' \
      '\zs' + VIM::regex_escape(s) + '\ze' \
      '\%(\s*$\|' + @@COLUMN_SEPARATOR + '\)'


        VIM::command 'syn clear LustyExpGrepMatch'

        if not @matched_strings.empty?
          sub_regexes = @matched_strings.map { |s| VIM::regex_escape(s) }
          syntax_regex = '\%(' + sub_regexes.join('\|') + '\)'
          VIM::command "syn match LustyExpGrepMatch \"#{syntax_regex}\""
        end
      end
    end

    # STEVE make it a class function?
    # STEVE duplicated from BufferExplorer
    def common_prefix(entries)
      prefix = entries[0].full_name
      entries.each do |entry|
        full_name = entry.full_name
        for i in 0...prefix.length
          if full_name.length <= i or prefix[i] != full_name[i]
            prefix = prefix[0...i]
            prefix = prefix[0..(prefix.rindex('/') or -1)]
            break
          end
        end
      end
      return prefix
    end

    # STEVE make it a class function?
    # STEVE duplicated from BufferExplorer
    def compute_buffer_entries
      buffer_entries = []
      (0..VIM::Buffer.count-1).each do |i|
        buffer_entries << GrepEntry.new(VIM::Buffer[i])
      end

      # Shorten each buffer name by removing all path elements which are not
      # needed to differentiate a given name from other names.  This usually
      # results in only the basename shown, but if several buffers of the
      # same basename are opened, there will be more.

      # Group the buffers by common basename
      common_base = Hash.new { |hash, k| hash[k] = [] }
      buffer_entries.each do |entry|
        if entry.full_name
          basename = Pathname.new(entry.full_name).basename.to_s
          common_base[basename] << entry
        end
      end

      # Determine the longest common prefix for each basename group.
      basename_to_prefix = {}
      common_base.each do |base, entries|
        if entries.length > 1
          basename_to_prefix[base] = common_prefix(entries)
        end
      end

      # Compute shortened buffer names by removing prefix, if possible.
      buffer_entries.each do |entry|
        full_name = entry.full_name

        short_name = if full_name.nil?
                       '[No Name]'
                     elsif Lusty::starts_with?(full_name, "scp://")
                       full_name
                     else
                       base = Pathname.new(full_name).basename.to_s
                       prefix = basename_to_prefix[base]

                       prefix ? full_name[prefix.length..-1] \
                              : base
                     end

        entry.short_name = short_name
        entry.name = short_name  # overridden later
      end

      buffer_entries
    end

    def current_abbreviation
      @prompt.input
    end

    # STEVE spaces result in no match
    def compute_sorted_matches
      abbrev = current_abbreviation()
      @matched_strings = []

      if abbrev == ''
        return @buffer_entries
      end

      begin
        regex = Regexp.compile(abbrev, Regexp::IGNORECASE)
      rescue RegexpError => e
        return []
      end


      # Used to avoid duplication
      highlight_hash = {}

      # Search through every line of every open buffer for the
      # given expression.
      grep_entries = []
      @buffer_entries.each do |entry|
        vim_buffer = entry.vim_buffer
        line_count = vim_buffer.count
        (1..line_count). each do |i|
          match = regex.match(vim_buffer[i])
          if match
            matched_str = match.to_s
            context = shrink_surrounding_context(vim_buffer[i], matched_str)

            grep_entry = entry.clone()
            grep_entry.line_number = i
            grep_entry.name = "#{grep_entry.short_name}:#{i}:#{context}"
            grep_entries << grep_entry

            # Keep track of all matched strings
            unless highlight_hash[matched_str]
              @matched_strings << matched_str
              highlight_hash[matched_str] = true
            end
          end
        end
      end

      return grep_entries
    end

    def shrink_surrounding_context(context, matched_str)
      pos = context.index(matched_str)
      Lusty::assert(pos) # STEVE remove

      start_index = [0, pos - 8].max
      end_index = [context.length, pos + matched_str.length + 8].min

      if start_index == 0
        if end_index == context.length
          context
        else
          "#{context[0...end_index]}..."
        end
      else
        if end_index == context.length
          "...#{context[start_index...end_index]}"
        else
          "...#{context[start_index...end_index]}..."
        end
      end
    end

    def open_entry(entry, open_mode)
      cleanup()
      Lusty::assert($curwin == @calling_window)

      number = entry.vim_buffer.number
      Lusty::assert(number)

      cmd = case open_mode
            when :current_tab
              "b"
            when :new_tab
              # For some reason just using tabe or e gives an error when
              # the alternate-file isn't set.
              "tab split | b"
            when :new_split
	      "sp | b"
            when :new_vsplit
	      "vs | b"
            else
              Lusty::assert(false, "bad open mode")
            end

      # Open buffer and go to the line number.
      VIM::command "silent #{cmd} #{number}"
      VIM::command "#{entry.line_number}"
    end
end
end

