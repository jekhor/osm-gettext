#!/usr/bin/ruby

# osm2po.rb --- extract translatable strings from OSM dump and save them in gettext PO format
#
# Copyright (C) 2009 Yauhen Kharuzhy <jekhor@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.
#

ENV['OSMLIBX_XML_PARSER']='Expat'

$:.unshift(File::expand_path(File.dirname($0) + '/lib'))

require 'yaml'
require 'OSM/objects'
require 'OSM/StreamParser'
require 'OSM/Database'
require 'rexml/document'

class String
	def gettext_escape!
		self.gsub!('"', '\"')
		self.gsub!("\t", '\t')
		self.gsub!("\r", '\r')
		self.gsub!("\n", '\n')
		self
	end
end

class Translator
	def initialize(rules_source, language_code)
		@lang = language_code
		rules = YAML::load(rules_source)

		@rules = Array.new
		rules.each {|r|
			r1 = Hash.new
			r1[:type] = r[:type]
			r1[:match] = eval "Proc.new {|e| #{r[:match]}}"
			if r[:tags].kind_of?(Array)
				r1[:tags] = r[:tags]
			else
				r1[:tags] = [r[:tags]]
			end
			@rules << r1
		}
	end

	def match(element)
		tags = []
		@rules.each {|rule|
			tags += rule[:tags] if (rule[:type] == 'any' or element.type == rule[:type]) and rule[:match].call(element)
		}
		tags
	end

	def xgettext(element)
		tags = match(element)

		s = ''

		tags.each {|t|
			next if element[t].nil?
			s = "\n"

			element.tags.each {|k, v|
				s += "#. #{k}=#{v}\n"
			}

			s += "#: #{element.type}:#{element.id}:#{t}\n"
			s += "msgid \"#{unnormalize(element[t]).gettext_escape!}\"\n"
			if element["#{t}:#{@lang}"].nil?
				s += "msgstr \"\"\n"
			else
				s += "msgstr \"#{unnormalize(element["#{t}:#{@lang}"]).gettext_escape!}\"\n"
			end
		}
		s
	end
	NAMECHAR = '[\-\w\d\.:]'
	NAME = "([\\w:]#{NAMECHAR}*)"
	NMTOKEN = "(?:#{NAMECHAR})+"
	NMTOKENS = "#{NMTOKEN}(\\s+#{NMTOKEN})*"
	REFERENCE = "(?:&#{NAME};|&#\\d+;|&#x[0-9a-fA-F]+;)"
	REFERENCE_RE = /#{REFERENCE}/
		DEFAULT_ENTITIES = { 
		'gt' => [/&gt;/, '&gt;', '>', />/], 
		'lt' => [/&lt;/, '&lt;', '<', /</], 
		'quot' => [/&quot;/, '&quot;', '"', /"/], 
		"apos" => [/&apos;/, "&apos;", "'", /'/] 
	}

	def entity( reference, entities )
		value = nil
		value = entities[ reference ] if entities
		if not value
			value = DEFAULT_ENTITIES[ reference ]
			value = value[2] if value
		end
		unnormalize( value, entities ) if value
	end


	# Unescapes all possible entities
	def unnormalize( string, entities=nil, filter=nil )
		rv = string.clone
		rv.gsub!( /\r\n?/, "\n" )
		matches = rv.scan( REFERENCE_RE )
		return rv if matches.size == 0
		rv.gsub!( /&#0*((?:\d+)|(?:x[a-fA-F0-9]+));/ ) {|m|
			m=$1
		m = "0#{m}" if m[0] == ?x
		[Integer(m)].pack('U*')
		}
		matches.collect!{|x|x[0]}.compact!
		if matches.size > 0
			matches.each do |entity_reference|
				unless filter and filter.include?(entity_reference)
					entity_value = entity( entity_reference, entities )
					if entity_value
						re = /&#{entity_reference};/
							rv.gsub!( re, entity_value )
					end
				end
			end
			matches.each do |entity_reference|
				unless filter and filter.include?(entity_reference)
					er = DEFAULT_ENTITIES[entity_reference]
					rv.gsub!( er[0], er[2] ) if er
				end
			end
			rv.gsub!( /&amp;/, '&' )
		end
		rv
	end
end

class TranslateCallbacks < OSM::Callbacks
	def initialize(rules_source, lang)
		@translator = Translator.new(rules_source, lang)
	end

	def node(node)
		return false unless node.is_tagged?
		print @translator.xgettext(node)
		true
	end

	def way(way)
		return false unless way.is_tagged?
		print @translator.xgettext(way)
		true
	end

	def relation(relation)
		return false unless relation.is_tagged?
		print @translator.xgettext(relation)
		true
	end
end

if ARGV.size != 2
	STDERR.puts "Usage: #{$0} <file.osm> <language code>"
	exit 1
end

cb = TranslateCallbacks.new(File.read(File.dirname($0) + '/rules.yaml'), ARGV[1])
parser = OSM::StreamParser.new(:filename => ARGV[0], :callbacks => cb)
parser.parse
