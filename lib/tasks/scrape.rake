# coding: utf-8

namespace :tribal_councils do
  desc 'Scrape tribal councils list'
  task :list => :environment do
    TribalCouncil.scrape_list
  end

  desc 'Scrape tribal councils details'
  task :details => :environment do
    TribalCouncil.scrape_details
  end
end

namespace :first_nations do
  desc 'Scrape First Nations list'
  task :list => :environment do
    FirstNation.scrape_list
  end

  desc 'Scrape First Nations details'
  task :details => :environment do
    FirstNation.scrape_details
  end

  desc 'Scrape First Nations data from Aboriginal Canada'
  task :extra => :environment do
    FirstNation.all.each do |item|
      item.scrape_extra
      item.save!
    end
  end
end

namespace :reserves do
  desc 'Scrape reserves list'
  task :list => :environment do
    Reserve.scrape_list
  end

  desc 'Scrape reserves details'
  task :details => :environment do
    Reserve.scrape_details
  end

  desc 'Scrape reserves data from Aboriginal Canada'
  task :extra => :environment do
    Reserve.all.each do |item|
      item.scrape_extra
      item.save!
    end
  end
end

namespace :members_of_parliament do
  desc 'Scrape members of parliament list'
  task :list => :environment do
    MemberOfParliament.scrape_list
  end

  desc 'Scrape members of parliament details'
  task :details => :environment do
    MemberOfParliament.scrape_details
  end
end

# @note 3007 locations from Canada Lands Survey System
#        582 locations from Google Maps links on Aboriginal Canada (46 more)
#        851 locations from Census Subdivisions (8 more)
namespace :other do
  require 'csv'
  require 'open-uri'
  require 'unicode_utils/upcase'

  # http://www.data.gc.ca/default.asp?lang=En&n=5175A6F0-1&xsl=datacataloguerecord&metaxsl=datacataloguerecord&formid=00A331DB-121B-445D-B119-35DBBE3EEDD9
  desc 'Import National Broadband Coverage Data'
  task :broadband => :environment do
    filename = File.join(Rails.root, 'data', 'National_Broadband_Data_Jan2012_Eng.csv')
    if File.exist? filename
      CSV.read(filename, encoding: 'utf-8', headers: true).select{|x| x['First Nation']}.each do |record|
        reserve_name = UnicodeUtils.upcase(record['First Nation']).gsub(/[[:space:]]+/, ' ')
        reserve_name = {
          'AROLAND 83'                              => 'AROLAND INDIAN SETTLEMENT',
          'CHIPPEWAS OF THE THAMES FIRST NATION 42' => 'CHIPPEWA OF THE THAMES FIRST NATION INDIAN RESERVE',
          'ESSIPIT'                                 => 'INNUE ESSIPIT',
          'FORT VERMILLION 173B'                    => 'FORT VERMILION 173B',
          "KAPAWE'NO FIRST NATION (FREEMAN 150B)"   => "KAPAWE'NO FIRST NATION 150B",
          "KAPAWE'NO FIRST NATION (GROUARD 230)"    => "KAPAWE'NO FIRST NATION 230",
          "KAPAWE'NO FIRST NATION (HALCRO 150C)"    => "KAPAWE'NO FIRST NATION 150C",
          "KAPAWE'NO FIRST NATION (PAKASHAN 150D)"  => "KAPAWE'NO FIRST NATION 150D",
          'LA ROMAINE'                              => 'ROMAINE 2',
          'LAC-RAPIDE'                              => 'RAPID LAKE',
          'PIIKANI 147'                             => 'PIIKANI',
        }[reserve_name] || reserve_name

        row = DataRow.new table: 'Coverage', data: record.to_hash
        row.reserve = Reserve.find_by_name reserve_name
        if row.reserve.nil?
          fingerprint = Reserve.fingerprint reserve_name
          row.reserve = Reserve.find_by_fingerprint(fingerprint) if fingerprint.present?
        end
        if row.reserve.nil?
          candidates = Reserve.where('name LIKE ?', "#{reserve_name}%")
          row.reserve = candidates.first if candidates.size == 1
        end
        puts %(Couldn't find #{reserve_name.ljust 70} #{fingerprint}) if row.reserve.nil?
        row.save!
      end
    else
      puts "You must save as UTF-8 the National Broadband Coverage Data to data/ from http://www.data.gc.ca/default.asp?lang=En&n=5175A6F0-1&xsl=datacataloguerecord&metaxsl=datacataloguerecord&formid=00A331DB-121B-445D-B119-35DBBE3EEDD9"
    end
  end

  # Reserve locations from Canada Lands Survey System
  # http://clss.nrcan.gc.ca/geobase-eng.php
  desc 'Import coordinates from Canada Lands Survey System'
  task :locate => :environment do
    filename = File.join(Rails.root, 'data', 'al_ta_ca_shp_eng', 'AL_TA_CA_2_22_eng.shp')
    if File.exist? filename
      RGeo::Shapefile::Reader.open(filename) do |file|
        puts "Processing #{file.num_records} records..."
        index = 0
        file.each do |record|
          index += 1
          puts "On record #{index} at #{Time.now.strftime('%H:%M:%S')}" if index % 100 == 0
          # Land Claim centroids are long to calculate and match first nations, not reserves.
          next if record['ALTYPE'] == 'Land Claim'
          reserve = Reserve.find_by_number record['ALCODE'].to_i
          if reserve
            centroid = record.geometry.centroid
            reserve.set_latitude_and_longitude centroid.y, centroid.x
          else
            puts "Couldn't find #{record['NAME1'].ljust 65}#{record['ALCODE']}"
          end
        end
      end
    else
      puts "You must download and unzip the Canada Lands Survey System shapefile to data/ from http://clss.nrcan.gc.ca/geobase-eng.php"
    end
  end

  # Census subdivisions from Statistics Canada
  # http://www12.statcan.gc.ca/census-recensement/2011/geo/bound-limit/bound-limit-eng.cfm
  desc 'Import coordinates from Statistics Canada census subdivisions'
  task :statcan => :environment do
    filename = File.join(Rails.root, 'data', 'gcsd000a11a_e', 'gcsd000a11a_e.shp')
    if File.exist? filename
      RGeo::Shapefile::Reader.open(filename) do |file|
        puts "Processing #{file.num_records} records..."
        index = 0
        file.each do |record|
          index += 1
          puts "On record #{index} at #{Time.now.strftime('%H:%M:%S')}" if index % 500 == 0
          reserve = Reserve.find_by_name UnicodeUtils.upcase(record['CSDNAME'])
          if reserve
            centroid = record.geometry.centroid
            reserve.set_latitude_and_longitude(centroid.y, centroid.x) unless reserve.geocoded?
          end
        end
      end
    else
      puts "You must download and unzip the Census Subdivisions shapefile to data/ from http://www12.statcan.gc.ca/census-recensement/2011/geo/bound-limit/bound-limit-eng.cfm"
    end
  end

  desc 'Add Twitter accounts for Members of Parliament'
  task :twitter => :environment do
    CSV.foreach(File.join(Rails.root, 'data', 'federal.csv'), headers: true, encoding: 'utf-8') do |row|
      begin
        matches = [MemberOfParliament.find_by_constituency(row['Riding']) || MemberOfParliament.where('constituency LIKE ?', "#{row['Riding']}%").all].flatten
        if matches.size > 1
          puts %(Many matches for constituency "#{row['Riding']}": #{matches.map(&:constituency).to_sentence})
        elsif matches.size == 1
          unless matches.first.name == row['Name']
            puts %("#{matches.first.name}" (stored) doesn't match "#{row['Name']}")
          end
          matches.first.update_attribute :twitter, "http://twitter.com/#{row['Twitter'].sub(/\A@/, '')}"
        else
          puts %(No match for constituency "#{row['Riding']}")
        end
      end
    end
  end

  desc 'Find federal electoral district for each reserve'
  task :districts => :environment do
    Reserve.geocoded.unrepresented.all.each do |reserve|
      response = JSON.parse(RestClient.get 'http://api.vote.ca/api/beta/districts', params: {lat: reserve.latitude, lng: reserve.longitude})
      federal = response.find{|x| x['electoral_group']['level'] == 'Federal'}
      if federal
        begin
          reserve.update_attribute :member_of_parliament_id, MemberOfParliament.find_by_constituency!(federal['name']).id
        rescue ActiveRecord::RecordNotFound
          puts %(No match for constituency "#{federal['name']}")
        end
      else
        puts %(No match for reserve "#{reserve.name}" (#{reserve.number}))
      end
    end
  end

  # National Assessment of Water and Wastewater Systems in First Nation Communities
  # http://www.aadnc-aandc.gc.ca/eng/1313426883501
  desc 'Get National Assessment data or each reserve'
  task :assessment => :environment do
    headers = {
      # Individual First Nation Water Summary
      # Water System Information, Storage Information, Distribution System Information
      D1: %w(
        band_number band_name system_number system_name water_source
        treatment_class construction_year design_capacity actual_capacity
        max_daily_volume disinfection storage_type storage_capacity
        distribution_class population_served homes_piped homes_trucked
        number_of_trucks_in_service pipe_length pipe_length_per_connection
      ).map(&:to_sym),
      # Individual First Nation Wastewater Summary
      # Wastewater System Information
      D2: %w(
        band_number band_name system_number system_name construction_year
        receiver_name treatment_class design_capacity max_daily_volume
        wastewater_system_type wastewater_treatment_level
        wastewater_disinfection_chlorine wastewater_disinfection_uv
        discharge_frequency wastewater_sludge_treatment
      ).map(&:to_sym),
      # Individual First Nation Water Risk Summary
      E1: %w(
        band_number band_name system_number system_name water_source
        treatment_class source_risk design_risk operations_risk report_risk
        operator_risk final_risk_score
      ).map(&:to_sym),
      # Individual First Nation Wastewater Risk Summary
      E2: %w(
        band_number band_name system_number system_name receiver_type
        treatment_class effluent_risk design_risk operations_risk report_risk
        operator_risk final_risk_score
      ).map(&:to_sym),
      # Protocol and Servicing Costs
      F: %w(
        band_number band_name community_name current_population current_homes
        forecast_population forecast_homes zone_markup upgrade_to_protocol
        per_lot_upgrade_to_protocol recommended_servicing
        per_lot_recommended_servicing recommended_om per_lot_om
      ).map(&:to_sym),
    }
    offsets = {
      D1: 2,
      D2: 2,
      E1: 1,
      E2: 1,
      F: 1,
    }
    definitions = {
      'Atlantic' => {
        D1: 1314113533397,
        D2: 1314110702660,
        E1: 1314109175095,
        E2: 1314107811990,
        F: 1314107279728,
      },
      'Quebec' => {
        D1: 1314803394499,
        D2: 1314805074731,
        E1: 1314805939008,
        E2: 1314806422379,
        F: 1314806747219,
      },
      'Ontario' => {
        D1: 1314980372889,
        D2: 1314983298779,
        E1: 1314985112423,
        E2: 1314986491857,
        F: 1314987205360,
      },
      'Manitoba' => {
        D1: 1315323828369,
        D2: 1315325682402,
        E1: 1315326602568,
        E2: 1315326972669,
        F: 1315327625229,
      },
      'Saskatchewan' => {
        D1: 1315530975150,
        D2: 1315532271829,
        E1: 1315533276055,
        E2: 1315533694498,
        F: 1315534873076,
      },
      'Alberta' => {
        D1: 1315504260472,
        D2: 1315507039750,
        E1: 1315508036194,
        E2: 1315508624010,
        F: 1315509237811,
      },
      'British Columbia' => {
        D1: 1315616544441,
        D2: 1315618492442,
        E1: 1315621253969,
        E2: 1315621659651,
        F: 1315622140396,
      },
      'Yukon' => {
        D1: 1315613380808,
        D2: 1315614663440,
        E1: 1315615248425,
        E2: 1315615615822,
        F: 1315616040456,
      },
    }

    # Clean up last run
    DataRow.destroy_all

    set = {}
    definitions.each do |region,tables|
      puts "Scraping #{region} tables..."
      tables.each do |table_name,id|
        puts "Scraping table #{table_name}..."
        set[table_name] ||= {}
        offset = set[table_name].size
        doc = Scrapable::Helpers.parse "http://www.aadnc-aandc.gc.ca/eng/#{id}"
        doc.css('table.widthFull').each_with_index do |table,i|
          table.css("tr:gt(#{offsets[table_name]})").each_with_index do |tr,j|
            set[table_name][j + offset] ||= []
            set[table_name][j + offset] += tr.css(i.zero? ? 'td' : 'td:gt(2)').map do |td|
              text = td.text.sub(/\A[[:space:]]+\z/, '').gsub(/(?<=[A-Za-z])-[[:space:]]/, '').gsub("\n", ' ').squeeze(' ')
              number = text.gsub(/[$,]/, '')
              if number[/\A-?\d+\z/]
                Integer number
              elsif number[/\A-?[\d.]+\z/]
                Float number
              else
                text
              end
            end
          end
        end
      end
    end

    set.each do |table_name,rows|
      puts "Saving table #{table_name}..."
      rows.each do |_,values|
        row = DataRow.new table: table_name, data: Hash[headers[table_name].zip(values)]
        row.first_nation = FirstNation.find_by_number row.data[:band_number]
        reserve_name = row.data[:system_name] || row.data[:community_name]
        reserve_number = reserve_name[/\((\d+)\)\z/, 1]
        if reserve_number
          row.reserve = Reserve.find_by_number reserve_number
          puts %(Couldn't find #{reserve_name.ljust 70} #{reserve_number}) if row.reserve.nil?
        else
          row.reserve = Reserve.find_by_name reserve_name
          if row.reserve.nil?
            fingerprint = Reserve.fingerprint reserve_name
            row.reserve = Reserve.find_by_fingerprint(fingerprint) if fingerprint.present?
          end
          puts %(Couldn't find #{reserve_name.ljust 70} #{fingerprint}) if row.reserve.nil?
        end
        row.save!
      end
    end
  end
end
