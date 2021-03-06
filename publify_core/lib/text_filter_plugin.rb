# frozen_string_literal: true

require "publify_plugins"

class TextFilterPlugin
  class << self
    include PublifyPlugins
    include ActionView::Helpers::TextHelper
    include ActionView::Helpers::TagHelper
  end

  @@filter_map = {}
  def self.inherited(sub)
    if sub.to_s =~ /^Plugin/ || sub.to_s =~ /^PublifyApp::Textfilter/
      name = sub.short_name
      @@filter_map[name] = sub
    end
  end

  def self.filter_map
    @@filter_map
  end

  def self.available_filters
    filter_map.values
  end

  def self.available_filter_types
    unless @cached_filter_types
      types = { "macropre" => [],
                "macropost" => [],
                "markup" => [],
                "postprocess" => [],
                "other" => [] }

      available_filters.each { |filter| types[filter.filter_type].push(filter) }

      @cached_filter_types = types
    end
    @cached_filter_types
  end

  def self.macro_filters
    available_filters.select { |filter| TextFilterPlugin::Macro > filter }
  end

  plugin_display_name "Unknown Text Filter"
  plugin_description "Unknown Text Filter Description"

  def self.reloadable?
    false
  end

  # The name that needs to be used when refering to the plugin's
  # controller in render statements
  def self.component_name
    if to_s =~ /::([a-zA-Z]+)$/
      "plugins/textfilters/#{Regexp.last_match[1]}".downcase
    else
      raise "I don't know who I am: #{self}"
    end
  end

  # The name that's stored in the DB.  This is the final chunk of the
  # controller name, like 'markdown' or 'smartypants'.
  def self.short_name
    component_name.split(%r{/}).last
  end

  def self.filter_type
    "other"
  end

  def self.default_config
    {}
  end

  def self.help_text
    ""
  end

  def self.sanitize(*args)
    (@sanitizer ||= Rails::Html::WhiteListSanitizer.new).sanitize(*args)
  end

  def self.default_helper_module!; end

  # Look up a config paramater, falling back to the default as needed.
  def self.config_value(params, name)
    params[:filterparams][name] || default_config[name][:default]
  end

  def self.logger
    @logger ||= ::Rails.logger || Logger.new(STDOUT)
  end
end

class TextFilterPlugin::PostProcess < TextFilterPlugin
  def self.filter_type
    "postprocess"
  end
end

class TextFilterPlugin::Macro < TextFilterPlugin
  # Utility function -- hand it a XML string like <a href="foo" title="bar">
  # and it'll give you back { "href" => "foo", "title" => "bar" }
  def self.attributes_parse(string)
    attributes = {}

    string.gsub(/([^ =]+="[^"]*")/) do |match|
      key, value = match.split(/=/, 2)
      attributes[key] = value.delete('"')
    end

    string.gsub(/([^ =]+='[^']*')/) do |match|
      key, value = match.split(/=/, 2)
      attributes[key] = value.delete("'")
    end

    attributes
  end

  def self.filtertext(text)
    regex1 = %r{<publify:#{short_name}(?:[ \t][^>]*)?/>}
    regex2 = %r{<publify:#{short_name}([ \t][^>]*)?>(.*?)</publify:#{short_name}>}m

    new_text = text.gsub(regex1) do |match|
      macrofilter(attributes_parse(match))
    end

    new_text = new_text.gsub(regex2) do |_match|
      macrofilter(attributes_parse(Regexp.last_match[1].to_s), Regexp.last_match[2].to_s)
    end

    new_text
  end
end

class TextFilterPlugin::MacroPre < TextFilterPlugin::Macro
  def self.filter_type
    "macropre"
  end
end

class TextFilterPlugin::MacroPost < TextFilterPlugin::Macro
  def self.filter_type
    "macropost"
  end
end

class TextFilterPlugin::Markup < TextFilterPlugin
  def self.filter_type
    "markup"
  end
end

class PublifyApp
  class Textfilter
    class MacroPost < TextFilterPlugin
      plugin_display_name "MacroPost"
      plugin_description "Macro expansion meta-filter (post-markup)"

      def self.filtertext(text)
        macros = TextFilterPlugin.available_filter_types["macropost"]
        macros.reduce(text) do |new_text, macro|
          macro.filtertext(new_text)
        end
      end
    end

    class MacroPre < TextFilterPlugin
      plugin_display_name "MacroPre"
      plugin_description "Macro expansion meta-filter (pre-markup)"

      def self.filtertext(text)
        macros = TextFilterPlugin.available_filter_types["macropre"]
        macros.reduce(text) do |new_text, macro|
          macro.filtertext(new_text)
        end
      end
    end
  end
end
