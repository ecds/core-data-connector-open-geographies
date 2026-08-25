# frozen_string_literal: true

module CoreDataConnector
  module OpenGeographies
    module V1
      class PlacesController < ApplicationController
        def index
          @records = Array(
            Place.search(
              '*',
              where: { model_type: 'place', project_id: project_id },
              load: false,
            ),
          )
          render(json: @records)
        end

        def show
          @record = Place.search(
            '*',
            where: { model_type: 'place', project_id: project_id, slugs: params[:slug] },
            limit: 1,
            load: false,
          ).first
          render(json: @record, status: :ok) and return if @record

          render(json: {}, status: :not_found)
        end

        private

        # Resolves the URL's parameterized project slug (e.g.
        # "historic-rural-churches-of-georgia") to a real Project id, the same
        # way v0 identifies a project - via a parameterized match on Project#name,
        # since CoreDataConnector::Project has no dedicated slug column. v0 does
        # this match as a full-text ES query against a stored `project` field;
        # v1 resolves it once here instead and filters the shared index on the
        # real project_id foreign key, which is the actual tenant-scoping
        # mechanism the canonical schema calls for ("every query is filtered
        # server-side on project_id") rather than a fuzzy text match.
        def project_id
          @project_id ||= ::CoreDataConnector::Project.all.find { |p| p.name.parameterize == params[:project] }&.id
        end
      end
    end
  end
end
