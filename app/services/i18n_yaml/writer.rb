require "psych"

module I18nYaml
  # Writes an ordered list of Entry as a nested YAML document.
  # Branches are grouped by first appearance, so entries of a branch need not be contiguous.
  class Writer
    INDENT = "  ".freeze

    def self.write(entries)
      new(entries).to_s
    end

    def initialize(entries)
      @tree = {}
      entries.each do |entry|
        *parents, leaf = entry.key.split(".")
        node = parents.reduce(@tree) { |n, k| n[k] ||= {} }
        raise ArgumentError, "Key #{entry.key} is both a branch and a leaf" unless node.is_a?(Hash) && !node[leaf].is_a?(Hash)
        node[leaf] = entry
      end
    end

    def to_s
      out = +""
      emit(@tree, 0, out)
      out
    end

    private

    def emit(node, depth, out)
      pad = INDENT * depth
      node.each do |key, child|
        if child.is_a?(Hash)
          out << "#{pad}#{format_key(key)}:\n"
          emit(child, depth + 1, out)
        else
          child.note.to_s.each_line { |l| out << "#{pad}# #{l.chomp}".rstrip << "\n" } if child.note
          out << "#{pad}#{format_key(key)}:#{format_value(child.value, pad + INDENT)}\n"
        end
      end
    end

    def format_key(key)
      plain_safe?(key) ? key : quote(key)
    end

    def format_value(value, block_pad)
      return " #{value}" if plain_safe?(value)
      return block(value, block_pad) if value.include?("\n") && !value.start_with?(" ", "\n")

      " #{quote(value)}"
    end

    def block(value, pad)
      chomp = if value.end_with?("\n\n") then "+"
              elsif value.end_with?("\n") then ""
              else "-"
              end
      body = value.end_with?("\n") ? value.chomp : value
      lines = body.split("\n", -1).map { |l| l.empty? ? "" : pad + l }
      " |#{chomp}\n#{lines.join("\n")}"
    end

    def quote(value)
      escaped = value.gsub(/[\\"]/) { |c| "\\#{c}" }
                     .gsub("\n", "\\n").gsub("\t", "\\t")
                     .gsub(/[\x00-\x08\x0b-\x1f]/) { |c| format("\\x%02X", c.ord) }
      "\"#{escaped}\""
    end

    # A plain scalar is safe when YAML reads it back as the very same string
    def plain_safe?(value)
      return false if value.empty? || value != value.strip || value.include?("\n")

      Psych.safe_load("k: #{value}") == { "k" => value }
    rescue Psych::Exception
      false
    end
  end
end
