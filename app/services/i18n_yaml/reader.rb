require "psych"

module I18nYaml
  # Reads an OCL i18n YAML file into an ordered list of Entry.
  # Scalars are read raw (never coerced) : `no: No` gives "No", not false.
  class Reader
    def self.read_file(path)
      new(File.read(path)).entries
    end

    def initialize(source)
      @lines = source.lines
      @document = Psych.parse(source)
    end

    def entries
      parse
      @entries
    end

    # { "dotted.path" => comment } of the branches (mapping keys) with a comment right above them
    def branch_notes
      parse
      @branch_notes
    end

    private

    def parse
      return if @entries

      @entries = []
      @branch_notes = {}
      walk(@document.root, []) if @document && @document.root.is_a?(Psych::Nodes::Mapping)
    end

    def walk(mapping, path)
      mapping.children.each_slice(2) do |key_node, value_node|
        key_path = path + [key_node.value]
        case value_node
        when Psych::Nodes::Mapping
          note = note_before(key_node.start_line)
          @branch_notes[key_path.join(".")] = note if note
          walk(value_node, key_path)
        when Psych::Nodes::Scalar
          @entries << Entry.new(key: key_path.join("."), value: value_node.value, note: note_before(key_node.start_line))
        else
          raise ArgumentError, "Unsupported YAML node #{value_node.class} at #{key_path.join('.')}"
        end
      end
    end

    # Consecutive comment lines right above the key (start_line is 0-based)
    def note_before(line_index)
      comments = []
      i = line_index - 1
      while i >= 0 && @lines[i] =~ /\A\s*#\s?(.*)$/
        comments.unshift($1)
        i -= 1
      end
      comments.empty? ? nil : comments.join("\n")
    end
  end
end
