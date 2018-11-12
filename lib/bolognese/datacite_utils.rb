# frozen_string_literal: true

module Bolognese
  module DataciteUtils
    def datacite_xml
      @datacite_xml ||= Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
        xml.resource(root_attributes) do
          insert_work(xml)
        end
      end.to_xml
    end

    def datacite_errors(xml: nil, schema_version: nil)
      schema_version = schema_version.to_s.start_with?("http://datacite.org/schema/kernel") ? schema_version : "http://datacite.org/schema/kernel-4"
      kernel = schema_version.to_s.split("/").last
      filepath = File.expand_path("../../../resources/#{kernel}/metadata.xsd", __FILE__)
      schema = Nokogiri::XML::Schema(open(filepath))

      schema.validate(Nokogiri::XML(xml, nil, 'UTF-8')).map { |error| error.to_s }.unwrap
    rescue Nokogiri::XML::SyntaxError => e
      e.message
    end

    def insert_work(xml)
      insert_identifier(xml)
      insert_creators(xml)
      insert_titles(xml)
      insert_publisher(xml)
      insert_publication_year(xml)
      insert_resource_type(xml)
      insert_alternate_identifiers(xml)
      insert_subjects(xml)
      insert_contributors(xml)
      insert_funding_references(xml)
      insert_dates(xml)
      insert_related_identifiers(xml)
      insert_version(xml)
      insert_rights_list(xml)
      insert_descriptions(xml)
    end

    def insert_identifier(xml)
      xml.identifier(doi, 'identifierType' => "DOI")
    end

    def insert_creators(xml)
      xml.creators do
        Array.wrap(creator).each do |au|
          xml.creator do
            insert_person(xml, au, "creator")
          end
        end
      end
    end

    def insert_contributors(xml)
      return xml unless contributor.present?

      xml.contributors do
        Array.wrap(contributor).each do |con|
          xml.contributor("contributorType" => con["contributor_type"] || "Other") do
            insert_person(xml, con, "contributor")
          end
        end
      end
    end

    def insert_person(xml, person, type)
      person_name = person["familyName"].present? ? [person["familyName"], person["givenName"]].compact.join(", ") : person["name"]
      attributes = person["type"].present? ? { "nameType" => person["type"] + "al" } : {}

      xml.send(type + "Name", person_name, attributes)
      xml.givenName(person["givenName"]) if person["givenName"].present?
      xml.familyName(person["familyName"]) if person["familyName"].present?
      xml.nameIdentifier(person["id"], 'schemeURI' => 'http://orcid.org/', 'nameIdentifierScheme' => 'ORCID') if person["id"].present?
    end

    def insert_titles(xml)
      xml.titles do
        Array.wrap(titles).each do |title|
          if title.is_a?(Hash)
            t = title
          else
            t = {}
            t["title"] = title
          end

          attributes = { 'titleType' => t["title_type"], 'lang' => t["lang"] }.compact
          xml.title(t["title"], attributes)
        end
      end
    end

    def insert_publisher(xml)
      xml.publisher(publisher || periodical && periodical["title"])
    end

    def insert_publication_year(xml)
      xml.publicationYear(publication_year)
    end

    def insert_resource_type(xml)
      return xml unless types["type"].present?

      xml.resourceType(types["resource_type"] || types["type"],
        'resourceTypeGeneral' => types["resource_type_general"] || Metadata::SO_TO_DC_TRANSLATIONS[types["type"]] || "Other")
    end

    def insert_alternate_identifiers(xml)
      return xml unless alternate_identifiers.present?

      xml.alternateIdentifiers do
        Array.wrap(alternate_identifiers).each do |alternate_identifier|
          xml.alternateIdentifier(alternate_identifier["alternate_identifier"], 'alternateIdentifierType' => alternate_identifier["alternate_identifier_type"])
        end
      end
    end

    def insert_dates(xml)
      return xml unless Array.wrap(dates).present?

      xml.dates do
        Array.wrap(dates).each do |date|
          attributes = { 'dateType' => date["date_type"] || "Issued", 'dateInformation' => date["date_information"] }.compact
          xml.date(date["date"], attributes)
        end
      end
    end

    def insert_funding_references(xml)
      return xml unless Array.wrap(funding_references).present?

      xml.fundingReferences do
        Array.wrap(funding_references).each do |funding_reference|
          xml.fundingReference do
            xml.funderName(funding_reference["funder_name"])
            xml.funderIdentifier(funding_reference["funder_identifier"], { "funderIdentifierType" => funding_reference["funder_identifier_type"] }.compact) if funding_reference["funder_identifier"].present?
            xml.awardNumber(funding_reference["award_number"], { "awardURI" => funding_reference["award_uri"] }.compact) if funding_reference["award_number"].present? || funding_reference["award_uri"].present?
            xml.awardTitle(funding_reference["award_title"]) if funding_reference["award_title"].present?
          end
        end
      end
    end

    def insert_subjects(xml)
      return xml unless subjects.present?

      xml.subjects do
        subjects.each do |subject|
          if subject.is_a?(Hash)
            s = subject
          else
            s = {}
            s["subject"] = subject
          end

          attributes = { "subjectScheme" => s["subject_scheme"], "schemeURI" => s["scheme_uri"], "valueURI" => s["value_uri"], "lang" => s["lang"] }.compact

          xml.subject(s["subject"], attributes)
        end
      end
    end

    def insert_version(xml)
      return xml unless version.present?

      xml.version(version)
    end

    def insert_related_identifiers(xml)
      return xml unless related_identifiers.present?

      xml.relatedIdentifiers do
        related_identifiers.each do |related_identifier|
          attributes = {
            'relatedIdentifierType' => related_identifier["related_identifier_type"],
            'relationType' => related_identifier["relation_type"],
            'resourceTypeGeneral' => related_identifier["resource_type_general"] }.compact

          attributes.merge({ 'relatedMetadataScheme' => related_identifier["related_metadata_schema"],
            'schemeURI' => related_identifier["scheme_uri"],
            'schemeType' => related_identifier["scheme_type"]}.compact) if %w(HasMetadata IsMetadataFor).include?(related_identifier["relation_type"])

          xml.relatedIdentifier(related_identifier["related_identifier"], attributes)
        end
      end
    end

    def insert_rights_list(xml)
      return xml unless rights_list.present?

      xml.rightsList do
        Array.wrap(rights_list).each do |rights|
          if rights.is_a?(Hash)
            r = rights
          else
            r = {}
            r["rights"] = rights
            r["rights_uri"] = normalize_id(rights)
          end

          attributes = { 'rightsURI' => r["rights_uri"], 'lang' => r["lang"] }.compact

          xml.rights(r["rights"], attributes)
        end
      end
    end

    def insert_descriptions(xml)
      return xml unless descriptions.present? || periodical && periodical["title"].present?

      xml.descriptions do
        if periodical && periodical["title"].present?
          xml.description(periodical["title"], 'descriptionType' => "SeriesInformation")
        end

        Array.wrap(descriptions).each do |description|
          if description.is_a?(Hash)
            d = description
          else
            d = {}
            d["description"] = description
            d["description_type"] = "Abstract"
          end

          attributes = { 'lang' => d["lang"], 'descriptionType' => d["description_type"] || "Abstract" }.compact

          xml.description(d["description"], attributes)
        end
      end
    end

    def root_attributes
      { :'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
        :'xsi:schemaLocation' => 'http://datacite.org/schema/kernel-4 http://schema.datacite.org/meta/kernel-4/metadata.xsd',
        :'xmlns' => 'http://datacite.org/schema/kernel-4' }
    end
  end
end
