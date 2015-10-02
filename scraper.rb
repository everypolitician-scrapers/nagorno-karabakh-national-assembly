#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
require 'colorize'
require 'pry'
require 'mechanize'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def date_from(text)
  return if text.to_s.empty?
  Date.parse(text).to_s rescue ''
end

def scrape_list(agent, fields)
  noko = agent.page.parser
  people = noko.css('div#deputy td.name a[href*="deputy/"]/@href').map do |href|
    link = URI.join "http://nankr.am/", href
    scrape_person(link, agent, fields)
  end
  return people
end

def scrape_person(url, agent, fields)
  agent.get(url)
  noko = agent.page.parser

  data = { 
    id: File.basename(url.to_s),
    name: noko.css('div.name').first.text.tidy,
    image: noko.css('div.photo img/@src').first.text,
    term: 6,
    source: agent.page.uri.to_s,
  }

  fields.each do |k, v|
    data[k] = noko.xpath('//td[@class="field" and text()="%s"]/following-sibling::td' % v).text.tidy
  end

  data[:birth_date] &&= date_from(data[:birth_date])
  data[:image] = URI.join( "http://nankr.am/", data[:image]).to_s unless data[:image].to_s.empty?
  return data
end

def scrape_lang(code, lang, fields)
  agent = Mechanize.new
  agent.request_headers = { 'Referer' => 'http://nankr.am/deputy/' }
  agent.get('http://nankr.am/?lang=%s' % code)
  scrape_list(agent, fields).each { |p| p["name__#{lang}".to_sym] = p[:name] }
end

eng = scrape_lang('eng', 'en', { 
  area: 'Electoral system, district',
  birth_date: 'Date of birth',
  party: 'Party',
  faction: 'Factions',
  email: 'E-mail',
})

rus = scrape_lang('rus', 'ru', { 
  district__ru: 'Избирательная система, округ',
  party__ru: 'Партия',
  faction__ru: 'Фракции',
})

arm = scrape_lang('arm', 'hy', { 
  district__hy: 'Ընտրակարգ, ընտրատարածք',
  party__hy: 'Կուսակցություն',
  faction__hy: 'Խմբակցություն',
})

arm.each do |p|
  data = p.merge( rus.find { |r| r[:id] == p[:id] } ).merge( eng.find { |e| e[:id] == p[:id] } )
  ScraperWiki.save_sqlite([:id, :term], data)
end

