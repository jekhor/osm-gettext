#!/usr/bin/ruby

# po2osm.rb --- convert translated string from PO back to OSM
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

class POParser
	def initialize
	end

	def parse(io)
		entries = []
		entry = nil
		io.each_line {|line|
			line.chomp!
			if line.empty?
				entries << entry unless entry.nil?
				entry = Hash.new
				next
			end

			if line[0, 3] == '#: '
				entry[:ref] = line.split(/\s/, 2)[1]
				entry[:osmtype], entry[:osmid], entry[:osmtag] = entry[:ref].split(':', 3)
				next
			end

			if line[0, 6] == "msgid "
				entry[:msgid] = unescape(line.split(/\s/, 2)[1][1..-2])
				next
			end

			if line[0, 7] == "msgstr "
				entry[:msgstr] = unescape(line.split(/\s/, 2)[1][1..-2])
				next
			end
		}
		entries << entry unless entry.nil?

		entries
	end

	private
	def unescape(orig)
		ret = orig.gsub(/\\n/, "\n")
		ret.gsub!(/\\t/, "\t")
		ret.gsub!(/\\r/, "\r")
		ret.gsub!(/\\"/, "\"")
		ret
	end
end

require 'rexml/document'

class PO2OSM
	def initialize(po, osm, lang)
		@po = po
		@osm = osm
		@lang = lang

		@po_parser = POParser.new
	end

	def merge
		entries = @po_parser.parse(@po)

		id_hash = {'way' =>{}, 'node'=>{}, 'relation'=>{}}
		entries.each {|e|
			next if e[:msgstr].empty?
			id = e[:osmid]
			type = e[:osmtype]
			id_hash[type][id] = [] if id_hash[type][id].nil?
			id_hash[type][id] << e
		}

		STDERR.puts "Parsing OSM..."
		doc = REXML::Document.new(@osm)
		STDERR.puts "done"

		doc.elements.each('osm/*') {|element|

			next unless element.name =~ /node|way|relation/

			if po_entries = id_hash[element.name][element.attributes['id']] then
				modified = false
				po_entries.each {|entry|
					found = false
					element.elements.each {|e|
						if e.name == 'tag' and e.attributes['k'] == "#{entry[:osmtag]}:#{@lang}" then
							if e.attributes['value'] != entry[:msgstr] 
								e.attributes['value'] = entry[:msgstr] 
								modified = true
							end
							found = true
							break
						end
					}
					if !found
						e = REXML::Element.new("tag")
						element.elements << e
						e.attributes['k'] = "#{entry[:osmtag]}:#{@lang}"
						e.attributes['v'] = entry[:msgstr] 
						modified = true
					end
					element.attributes['action'] = 'modify' if modified
				}
			end
		}

		doc.to_s
	end
end

if ARGV.size != 3
	STDERR.puts "Usage: #{$0} <file.osm> <file.po> <language code>"
	exit 1
end

osm = File.open(ARGV[0])
po = File.open(ARGV[1])
lang = ARGV[2]
p = PO2OSM.new(po, osm, lang)

puts p.merge
