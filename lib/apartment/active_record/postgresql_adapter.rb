# frozen_string_literal: true

# rubocop:disable Style/ClassAndModuleChildren

# NOTE: This patch is meant to remove any schema_prefix appart from the ones for
# excluded models. The schema_prefix would be resolved by apartment's setting
# of search path
module Apartment::PostgreSqlAdapterSchemaPrefixPatch
  def default_sequence_name(table, _column)
    res = super
    schema_prefix = "#{Apartment::Tenant.current}."
    default_tenant_prefix = "#{Apartment::Tenant.default_tenant}."

    # NOTE: Excluded models should always access the sequence from the default
    # tenant schema
    if excluded_model?(table)
      res.sub!(schema_prefix, default_tenant_prefix) if schema_prefix != default_tenant_prefix
      return res
    end

    res.delete_prefix!(schema_prefix) if res&.starts_with?(schema_prefix)

    res
  end

  private

  def excluded_model?(table)
    Apartment.excluded_models.any? { |m| m.constantize.table_name == table }
  end
end

module Apartment::PostgreSqlAdapterEnumPatch
  def enum_types
    query = <<~SQL
      SELECT
        type.typname AS name,
        string_agg(enum.enumlabel, ',' ORDER BY enum.enumsortorder) AS value
      FROM pg_enum AS enum
      JOIN pg_type AS type
        ON (type.oid = enum.enumtypid)
      GROUP BY type.typname;
    SQL
    # Make enum values unique since each schema will have the enum declared
    exec_query(query, "SCHEMA").cast_values.map { |name, value| [name, value.split(",").uniq.join(",")] }
  end

  # Taken from https://github.com/alassek/activerecord-pg_enum/blob/6e0daf6/lib/active_record/pg_enum/schema_statements.rb#L14-L18
  def create_enum(name, values)
    execute("CREATE TYPE #{name} AS ENUM (#{Array(values).map { |v| "'#{v}'" }.join(", ")})").tap {
      reload_type_map
    }
  end
end

require 'active_record/connection_adapters/postgresql_adapter'

# NOTE: inject these into postgresql adapters
class ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
  include Apartment::PostgreSqlAdapterSchemaPrefixPatch
  include Apartment::PostgreSqlAdapterEnumPatch if ActiveRecord.version.release >= Gem::Version.new('7.0')
end
# rubocop:enable Style/ClassAndModuleChildren
