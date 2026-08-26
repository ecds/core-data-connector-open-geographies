# frozen_string_literal: true

module CoreDataConnector
  module OpenGeographies
    class Engine < ::Rails::Engine
      require 'rails/all'
      isolate_namespace CoreDataConnector::OpenGeographies

      # Without this, `rails db:migrate` in the host app never sees
      # db/migrate here at all - this engine had no migrations of its own
      # until ProjectModelRole, so nothing surfaced the gap before now.
      initializer :append_migrations do |app|
        unless app.root.to_s.match?(root.to_s)
          config.paths['db/migrate'].expanded.each do |expanded_path|
            app.config.paths['db/migrate'] << expanded_path
          end
        end
      end
    end
  end
end
