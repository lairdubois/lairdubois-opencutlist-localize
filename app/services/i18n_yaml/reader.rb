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
      return [] unless @document && @document.root.is_a?(Psych::Nodes::Mapping)

      out = []
      walk(@document.root, [], out)
      out
    end

    private

    def walk(mapping, path, out)
      mapping.children.each_slice(2) do |key_node, value_node|
        key_path = path + [key_node.value]
        case value_node
        when Psych::Nodes::Mapping
          walk(value_node, key_path, out)
        when Psych::Nodes::Scalar
          out << Entry.new(key: key_path.join("."), value: value_node.value, note: note_before(key_node.start_line))
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
