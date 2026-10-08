# Nested view of the active units, built from their dotted keys
class UnitTree
  # first = first unit of the subtree ; continued = the subtree started on a previous page
  Node = Struct.new(:name, :path, :unit, :children, :stats, :first, :continued, keyword_init: true) do
    def branch?
      children.any?
    end
  end

  # stats per unit id : [translated count, outdated count]
  def initialize(units, stats)
    @root = Node.new(name: nil, path: nil, children: {}, stats: [0, 0, 0], first: units.first)
    units.each do |unit|
      parts = unit.key.split(".")
      node = parts.each_with_index.reduce(@root) do |parent, (part, i)|
        parent.children[part] ||= Node.new(name: part, path: parts.first(i + 1).join("."), children: {}, stats: [0, 0, 0], first: unit)
      end
      node.unit = unit
      translated, outdated = stats.fetch(unit.id, [0, 0])
      ([@root] + parts.each_index.map { |i| dig(parts.first(i + 1)) }).each do |n|
        n.stats[0] += 1
        n.stats[1] += translated
        n.stats[2] += outdated
      end
    end
  end

  def roots
    @root.children.values
  end

  def total
    @root.stats
  end

  def find(path)
    dig(path.split("."))
  end

  # For a tree built from a page of `full`'s units : branch stats count the whole list, not the page
  def complete_from(full)
    each_node(@root) do |node|
      source = full.find(node.path)
      node.stats = source.stats
      node.continued = source.first != node.first
    end
    self
  end

  private

  def dig(parts)
    parts.reduce(@root) { |n, p| n&.children&.[](p) }
  end

  def each_node(node, &block)
    node.children.each_value do |child|
      block.call(child)
      each_node(child, &block)
    end
  end
end
