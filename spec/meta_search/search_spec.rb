require 'spec_helper'

module MetaSearch
  describe Search do

    describe '#build' do
      it 'creates Conditions for top-level attributes' do
        search = Search.new(Person, :name_eq => 'Ernie')
        condition = search.base[:name_eq]
        condition.should be_a Nodes::Condition
        condition.predicate.name.should eq 'eq'
        condition.attributes.first.name.should eq 'name'
        condition.value.should eq 'Ernie'
      end

      it 'creates Conditions for association attributes' do
        search = Search.new(Person, :children_name_eq => 'Ernie')
        condition = search.base[:children_name_eq]
        condition.should be_a Nodes::Condition
        condition.predicate.name.should eq 'eq'
        condition.attributes.first.name.should eq 'children_name'
        condition.value.should eq 'Ernie'
      end

      it 'discards empty conditions' do
        search = Search.new(Person, :children_name_eq => '')
        condition = search.base[:children_name_eq]
        condition.should be_nil
      end

      it 'accepts arrays of groupings' do
        search = Search.new(Person,
          :o => [
            {:name_eq => 'Ernie', :children_name_eq => 'Ernie'},
            {:name_eq => 'Bert', :children_name_eq => 'Bert'},
          ]
        )
        ors = search.ors
        ors.should have(2).items
        or1, or2 = ors
        or1.should be_a Nodes::Or
        or2.should be_a Nodes::Or
      end

      it 'accepts "attributes" hashes for groupings' do
        search = Search.new(Person,
          :o => {
            '0' => {:name_eq => 'Ernie', :children_name_eq => 'Ernie'},
            '1' => {:name_eq => 'Bert', :children_name_eq => 'Bert'},
          }
        )
        ors = search.ors
        ors.should have(2).items
        or1, or2 = ors
        or1.should be_a Nodes::Or
        or2.should be_a Nodes::Or
      end

      it 'accepts "attributes" hashes for conditions' do
        search = Search.new(Person,
          :c => {
            '0' => {:a => ['name'], :p => 'eq', :v => ['Ernie']},
            '1' => {:a => ['children_name', 'parent_name'], :p => 'eq', :v => ['Ernie'], :m => 'or'}
          }
        )
        conditions = search.base.conditions
        conditions.should have(2).items
        conditions.map {|c| c.class}.should eq [Nodes::Condition, Nodes::Condition]
      end
    end

    describe '#result' do
      it 'evaluates conditions contextually' do
        search = Search.new(Person, :children_name_eq => 'Ernie')
        search.result.should be_an ActiveRecord::Relation
        where = search.result.where_values.first
        where.to_sql.should match /"children_people"\."name" = 'Ernie'/
      end

      it 'evaluates compound conditions contextually' do
        search = Search.new(Person, :children_name_or_name_eq => 'Ernie')
        search.result.should be_an ActiveRecord::Relation
        where = search.result.where_values.first
        where.to_sql.should match /"children_people"\."name" = 'Ernie' OR "people"\."name" = 'Ernie'/
      end

      it 'evaluates nested conditions' do
        search = Search.new(Person, :children_name_eq => 'Ernie',
          :o => [{
            :name_eq => 'Ernie',
            :children_children_name_eq => 'Ernie'
          }]
        )
        search.result.should be_an ActiveRecord::Relation
        where = search.result.where_values.first
        where.to_sql.should match /\("children_people"."name" = 'Ernie' AND \("people"."name" = 'Ernie' OR "children_people_2"."name" = 'Ernie'\)\)/
      end

      it 'evaluates arrays of groupings' do
        search = Search.new(Person,
          :o => [
            {:name_eq => 'Ernie', :children_name_eq => 'Ernie'},
            {:name_eq => 'Bert', :children_name_eq => 'Bert'},
          ]
        )
        search.result.should be_an ActiveRecord::Relation
        where = search.result.where_values.first
        where.to_sql.should match /\(\("people"."name" = 'Ernie' OR "children_people"."name" = 'Ernie'\) AND \("people"."name" = 'Bert' OR "children_people"."name" = 'Bert'\)\)/
      end
    end

    describe '#sorts=' do
      before do
        @s = Search.new(Person)
      end

      it 'creates sorts based on a single attribute/direction' do
        @s.sorts = 'id desc'
        @s.sorts.should have(1).item
        sort = @s.sorts.first
        sort.should be_a Nodes::Sort
        sort.name.should eq 'id'
        sort.dir.should eq 'desc'
      end

      it 'creates sorts based on multiple attributes/directions in array format' do
        @s.sorts = ['id desc', 'name asc']
        @s.sorts.should have(2).items
        sort1, sort2 = @s.sorts
        sort1.should be_a Nodes::Sort
        sort1.name.should eq 'id'
        sort1.dir.should eq 'desc'
        sort2.should be_a Nodes::Sort
        sort2.name.should eq 'name'
        sort2.dir.should eq 'asc'
      end

      it 'creates sorts based on multiple attributes/directions in hash format' do
        @s.sorts = {
          '0' => {
            :name => 'id',
            :dir => 'desc'
          },
          '1' => {
            :name => 'name',
            :dir => 'asc'
          }
        }
        @s.sorts.should have(2).items
        sort1, sort2 = @s.sorts
        sort1.should be_a Nodes::Sort
        sort1.name.should eq 'id'
        sort1.dir.should eq 'desc'
        sort2.should be_a Nodes::Sort
        sort2.name.should eq 'name'
        sort2.dir.should eq 'asc'
      end
    end

    describe '#method_missing' do
      before do
        @s = Search.new(Person)
      end

      it 'raises NoMethodError when sent an invalid attribute' do
        expect {@s.blah}.to raise_error NoMethodError
      end

      it 'sets condition attributes when sent valid attributes' do
        @s.name_eq = 'Ernie'
        @s.name_eq.should eq 'Ernie'
      end

      it 'allows chaining to access nested conditions' do
        @s.ors = [{:name_eq => 'Ernie', :children_name_eq => 'Ernie'}]
        @s.ors.first.name_eq.should eq 'Ernie'
        @s.ors.first.children_name_eq.should eq 'Ernie'
      end
    end

  end
end