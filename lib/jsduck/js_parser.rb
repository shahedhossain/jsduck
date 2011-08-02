require 'jsduck/lexer'
require 'jsduck/doc_parser'
require 'jsduck/js_literal_parser'
require 'jsduck/js_literal_builder'

module JsDuck

  class JsParser < JsLiteralParser
    def initialize(input)
      super(input)
      @doc_parser = DocParser.new
      @docs = []
    end

    # Parses the whole JavaScript block and returns array where for
    # each doc-comment there is a hash of three values: the comment
    # structure created by DocParser, number of the line where the
    # comment starts, and parsed structure of the code that
    # immediately follows the comment.
    #
    # For example with the following JavaScript input:
    #
    # /**
    #  * @param {String} foo
    #  */
    # MyClass.doIt = function(foo, bar) {
    # }
    #
    # The return value of this function will be:
    #
    # [
    #   {
    #     :comment => [
    #       {:tagname => :default, :doc => "Method description"},
    #       {:tagname => :return, :type => "Number", :doc => ""},
    #     ],
    #     :linenr => 1,
    #     :code => {
    #       :type => :assignment,
    #       :left => ["MyClass", "doIt"],
    #       :right => {
    #         :type => :function,
    #         :name => nil,
    #         :params => [
    #           {:name => "foo"},
    #           {:name => "bar"}
    #         ]
    #       }
    #     }
    #   }
    # ]
    #
    def parse
      while !@lex.empty? do
        if look(:doc_comment)
          comment = @lex.next(true)
          @docs << {
            :comment => @doc_parser.parse(comment[:value]),
            :linenr => comment[:linenr],
            :code => code_block
          }
        else
          @lex.next
        end
      end
      @docs
    end

    # The following is a recursive-descent parser for JavaScript that
    # can possibly follow a doc-comment

    # <code-block> := <function> | <var-declaration> | <ext-define> |
    #                 <assignment> | <property-literal>
    def code_block
      if look("function")
        function
      elsif look("var")
        var_declaration
      elsif look("Ext", ".", "define", "(", :string)
        ext_define
      elsif look("Ext", ".", "ClassManager", ".", "create", "(", :string)
        ext_define
      elsif look(:ident, ":") || look(:string, ":")
        property_literal
      elsif look(",", :ident, ":") || look(",", :string, ":")
        match(",")
        property_literal
      elsif look(:ident) || look("this")
        maybe_assignment
      elsif look(:string)
        {:type => :assignment, :left => [match(:string)[:value]]}
      else
        {:type => :nop}
      end
    end

    # <function> := "function" [ <ident> ] <function-parameters> <function-body>
    def function
      match("function")
      return {
        :type => :function,
        :name => look(:ident) ? match(:ident)[:value] : nil,
        :params => function_parameters,
        :body => function_body,
      }
    end

    # <function-parameters> := "(" [ <ident> [ "," <ident> ]* ] ")"
    def function_parameters
      match("(")
      params = look(:ident) ? [{:name => match(:ident)[:value]}] : []
      while look(",", :ident) do
        params << {:name => match(",", :ident)[:value]}
      end
      match(")")
      return params
    end

    # <function-body> := "{" ...
    def function_body
      match("{")
    end

    # <var-declaration> := "var" <assignment>
    def var_declaration
      match("var")
      maybe_assignment
    end

    # <maybe-assignment> := <ident-chain> [ "=" <expression> ]
    def maybe_assignment
      left = ident_chain
      if look("=")
        match("=")
        right = expression
      end
      return {
        :type => :assignment,
        :left => left,
        :right => right,
      }
    end

    # <ident-chain> := [ "this" | <ident> ]  [ "." <ident> ]*
    def ident_chain
      if look("this")
        chain = [match("this")[:value]]
      else
        chain = [match(:ident)[:value]]
      end

      while look(".", :ident) do
        chain << match(".", :ident)[:value]
      end
      return chain
    end

    # <expression> := <function> | <ext-extend> | <literal>
    def expression
      if look("function")
        function
      elsif look("Ext", ".", "extend")
        ext_extend
      else
        my_literal
      end
    end

    # <literal> := ...see JsLiteralParser...
    def my_literal
      lit = literal
      return unless lit

      cls_map = {
        :string => "String",
        :number => "Number",
        :regex => "RegExp",
        :array => "Array",
        :object => "Object",
      }

      if cls_map[lit[:type]]
        cls = cls_map[lit[:type]]
      elsif lit[:type] == :ident && (lit[:value] == "true" || lit[:value] == "false")
        cls = "Boolean"
      else
        cls = nil
      end

      value = JsLiteralBuilder.new.to_s(lit)

      {:type => :literal, :class => cls, :value => value}
    end

    # <ext-extend> := "Ext" "." "extend" "(" <ident-chain> "," ...
    def ext_extend
      match("Ext", ".", "extend", "(")
      return {
        :type => :ext_extend,
        :extend => ident_chain,
      }
    end

    # <ext-define> := "Ext" "." ["define" | "ClassManager" "." "create" ] "(" <string> "," <ext-define-cfg>
    def ext_define
      match("Ext", ".");
      look("define") ? match("define") : match("ClassManager", ".", "create");
      name = match("(", :string)[:value]

      if look(",", "{")
        match(",")
        cfg = ext_define_cfg
      else
        cfg = {}
      end

      cfg[:type] = :ext_define
      cfg[:name] = name

      cfg
    end

    # <ext-define-cfg> := "{" ( <extend> | <mixins> | <alternate-class-name> | <alias> | <?> )*
    def ext_define_cfg
      match("{")
      cfg = {}
      found = true
      while found
        found = false
        if look("extend", ":", :string)
          cfg[:extend] = ext_define_extend
          found = true
        elsif look("mixins", ":", "{")
          cfg[:mixins] = ext_define_mixins
          found = true
        elsif look("alternateClassName", ":")
          cfg[:alternateClassNames] = ext_define_alternate_class_names
          found = true
        elsif look("alias", ":")
          cfg[:alias] = ext_define_alias
          found = true
        elsif look(:ident, ":")
          match(:ident, ":")
          found = literal
        end
        match(",") if look(",")
      end
      cfg
    end

    # <ext-define-extend> := "extend" ":" <string>
    def ext_define_extend
      match("extend", ":", :string)[:value]
    end

    # <ext-define-alternate-class-names> := "alternateClassName" ":" <string-or-list>
    def ext_define_alternate_class_names
      match("alternateClassName", ":")
      string_or_list
    end

    # <ext-define-alias> := "alias" ":" <string-or-list>
    def ext_define_alias
      match("alias", ":")
      string_or_list
    end

    # <string-or-list> := ( <string> | <array-literal> )
    def string_or_list
      lit = literal
      if lit && lit[:type] == :string
        [ lit[:value] ]
      elsif lit && lit[:type] == :array
        lit[:value].map {|x| x[:value] }
      else
        []
      end
    end

    # <ext-define-mixins> := "mixins" ":" <object-literal>
    def ext_define_mixins
      match("mixins", ":")
      lit = literal
      lit && lit[:value].map {|x| x[:value][:value] }
    end

    # <property-literal> := ( <ident> | <string> ) ":" <expression>
    def property_literal
      left = look(:ident) ? match(:ident)[:value] : match(:string)[:value]
      match(":")
      right = expression
      return {
        :type => :assignment,
        :left => [left],
        :right => right,
      }
    end

  end

end
