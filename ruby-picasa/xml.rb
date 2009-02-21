module RubyPicasa
  class Xml
    module Dsl
      def self.extended(target)
        target.init
      end

      def init
        parent = ancestors[1]
        if parent
          @collections = parent.instance_variable_get('@collections') || []
          @attributes = parent.instance_variable_get('@attributes') || []
          @flatten = parent.instance_variable_get('@flatten') || []
          @namespaces = parent.instance_variable_get('@namespaces') || []
          @types = parent.instance_variable_get('@types') || {}
        else
          @collections = []
          @attributes = []
          @flatten = []
          @namespaces = []
          @types = {}
        end
      end

      def has_one(name, type, qualified_name)
        set_type(qualified_name, type)
      end

      def has_many(name, type, qualified_name)
        @collections << qualified_name.to_s
        set_type(qualified_name, type)
        attribute name, true
      end

      def attributes(*names)
        names.each { |n| attribute n }
        @attributes
      end

      def attribute(name, collection = false)
        name = name.to_s.underscore
        @attributes << name
        module_eval %{
          def #{name}=(value)
            @attributes['#{name}'] = value
          end
          def #{name}
            @attributes['#{name}']#{ collection ? ' ||= []' : '' }
          end
        }
        name
      end

      def find_attribute(qualified_name, namespace, name)
        names = []
        plural = collection?(qualified_name)
        if plural
          if namespace
            names << "#{ namespace }_#{ name.pluralize }"
          end
          names << name.pluralize
        end
        if namespace
          names << "#{ namespace }_#{ name }"
        end
        names << name
        names.map { |n| n.underscore }.find do |n|
          @attributes.include? n.underscore
        end
      end

      def flatten(qualified_name)
        @flatten << qualified_name
      end

      def flatten?(qualified_name)
        @flatten.include? qualified_name
      end

      def namespace?(namespace)
        @namespaces.include? namespace
      end

      def namespaces(*namespaces)
        @namespaces += namespaces
      end

      def attribute_type(qualified_name)
        type = @types[qualified_name]
        if type and not type.is_a? Class
          type = "RubyPicasa::#{ type }".constantize rescue nil
          type ||= type.to_s.constantize
          @types[qualified_name] = type
        end
        type
      end

      def set_type(qualified_name, type)
        @types[qualified_name] = type
      end

      def collection?(qualified_name)
        @collections.include?(qualified_name)
      end

      def data
        [@attributes, @collections, @flatten, @namespaces, @types]
      end
    end

    def self.inherited(target)
      target.extend Dsl
    end

    def initialize(xml)
      @attributes = {}
      return if xml.nil?
      if xml.is_a? String
        xml = Nokogiri::XML(xml) 
        # skip the <?xml?> tag
        xml = xml.child if xml.name == 'document'
      end
      primary_xml_element(xml) if xml
    end

    def xml_text_to_value(value)
      value = value.strip
      case value
      when 'true'
        true
      when 'false'
        false
      when /\A\d{4}-\d\d-\d\dT(\d\d[:.]){3}\d{3}\w\Z/
        DateTime.parse(value)
      when /\A\d+\Z/
        value.to_i
      when /\A\d+\.\d+\Z/
        value.to_f
      else
        value
      end
    end
  end

  class AttributeParser < Xml
    def primary_xml_element(xml)
      xml.attributes.keys.each do |name|
        method = "#{ name }="
        if respond_to? method
          send(method, xml_text_to_value(xml[name]))
        end
      end
    end
  end

  class XmlParser < Xml
    def qualified_name(x)
      qn = x.name
      qn = "#{ x.namespace }:#{ x.name }" if x.namespace
      qn
    end

    def attribute_type(x)
      self.class.attribute_type qualified_name(x)
    end

    def flatten?(x)
      self.class.flatten?(qualified_name(x))
    end

    def collection?(x)
      self.class.collection?(qualified_name(x))
    end

    def namespace?(x)
      if x.namespace
        self.class.namespace?(x.namespace)
      else
        true
      end
    end

    def attribute(x)
      self.class.find_attribute(qualified_name(x), x.namespace, x.name)
    end

    def attributes
      self.class.attributes
    end

    def primary_xml_element(xml)
      parse_xml(xml.child)
    end

    def parse_xml(xml)
      while xml
        read_xml_element(xml)
        xml = xml.next
      end
    end

    def read_xml_element(x)
      return if x.is_a? Nokogiri::XML::Text
      return unless namespace?(x)
      if flatten?(x)
        parse_xml(x.child)
      elsif type = attribute_type(x)
        set_attribute(x) { type.new(x) }
      else
        set_attribute(x) { xml_text_to_value(x.text) }
      end
    end

    def set_attribute(x)
      if attr_name = attribute(x)
        if collection?(x)
          send(attr_name) << yield
        else
          send("#{attr_name}=", yield)
        end
      end
    end
  end
end
