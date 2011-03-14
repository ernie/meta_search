require 'meta_search/context'
require 'active_record'

module MetaSearch
  module Adapters
    module ActiveRecord
      class Context < ::MetaSearch::Context
        # Because the AR::Associations namespace is insane
        JoinDependency = ::ActiveRecord::Associations::JoinDependency
        JoinPart = JoinDependency::JoinPart
        JoinAssociation = JoinDependency::JoinAssociation

        def evaluate(search, opts = {})
          relation = @object.where(accept(search.base)).order(accept(search.sorts))
          opts[:distinct] ? relation.group(@klass.arel_table[@klass.primary_key]) : relation
        end

        def attribute_method?(str, klass = @klass)
          exists = false

          if column = get_column(str, klass)
            exists = true
          elsif (segments = str.split(/_/)).size > 1
            remainder = []
            found_assoc = nil
            while !found_assoc && remainder.unshift(segments.pop) && segments.size > 0 do
              if found_assoc = get_association(segments.join('_'), klass)
                exists = attribute_method?(remainder.join('_'), found_assoc.klass)
              end
            end
          end

          exists
        end

        def type_for(attr)
          return nil unless attr
          name    = attr.name.to_s
          table   = attr.relation.table_name

          unless @engine.connection_pool.table_exists?(table)
            raise "No table named #{table} exists"
          end

          @engine.connection_pool.columns_hash[table][name].type
        end

        private

        def klassify(obj)
          if Class === obj && ::ActiveRecord::Base > obj
            obj
          elsif obj.respond_to? :klass
            obj.klass
          elsif obj.respond_to? :active_record
            obj.active_record
          else
            raise ArgumentError, "Don't know how to klassify #{obj}"
          end
        end

        def get_attribute(str, parent = @base)
          attribute = nil

          if column = get_column(str, parent)
            attribute = parent.table[str]
          elsif (segments = str.split(/_/)).size > 1
            remainder = []
            found_assoc = nil
            while remainder.unshift(segments.pop) && segments.size > 0 && !found_assoc do
              if found_assoc = get_association(segments.join('_'), parent)
                join = build_or_find_association(found_assoc.name, parent)
                attribute = get_attribute(remainder.join('_'), join)
              end
            end
          end

          attribute
        end

        def get_column(str, parent = @base)
          klassify(parent).columns_hash[str]
        end

        def get_association(str, parent = @base)
          klassify(parent).reflect_on_all_associations.detect {|a| a.name.to_s == str}
        end

        def join_dependency(relation)
          if relation.respond_to?(:join_dependency) # MetaWhere will enable this
            relation.join_dependency
          else
            build_join_dependency(relation)
          end
        end

        def build_join_dependency(relation)
          buckets = relation.joins_values.group_by do |join|
            case join
            when String
              'string_join'
            when Hash, Symbol, Array
              'association_join'
            when ActiveRecord::Associations::JoinDependency::JoinAssociation
              'stashed_join'
            when Arel::Nodes::Join
              'join_node'
            else
              raise 'unknown class: %s' % join.class.name
            end
          end

          association_joins         = buckets['association_join'] || []
          stashed_association_joins = buckets['stashed_join'] || []
          join_nodes                = buckets['join_node'] || []
          string_joins              = (buckets['string_join'] || []).map { |x|
            x.strip
          }.uniq

          join_list = relation.send :custom_join_ast, relation.table.from(relation.table), string_joins

          join_dependency = JoinDependency.new(
            relation.klass,
            association_joins,
            join_list
          )

          join_nodes.each do |join|
            join_dependency.table_aliases[join.left.name.downcase] = 1
          end

          join_dependency.graft(*stashed_association_joins)
        end

        def build_or_find_association(name, parent = @base)
          found_association = @join_dependency.join_associations.detect do |assoc|
            assoc.reflection.name == name &&
            assoc.parent == parent
          end
          unless found_association
            @join_dependency.send(:build, name.to_sym, parent, Arel::Nodes::OuterJoin)
            found_association = @join_dependency.join_associations.last
            # Leverage the stashed association functionality in AR
            @object = @object.joins(found_association)
          end

          found_association
        end

      end
    end
  end
end