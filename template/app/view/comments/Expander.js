/**
 * The comments expander, showing the number of comments.
 */
Ext.define('Docs.view.comments.Expander', {
    alias: "widget.commentsExpander",
    extend: 'Ext.Component',
    requires: [
        'Docs.Comments',
        'Docs.view.comments.List'
    ],

    /**
     * @cfg {String} type
     * One of: "class", "guide", "video".
     */
    type: "class",

    /**
     * @cfg {String} className
     */
    /**
     * @cfg {String} memberId
     */
    /**
     * @cfg {Number} count
     */

    initComponent: function() {
        this.tpl = new Ext.XTemplate(
            '<div class="comments-div first-child" id="comments-{id}">',
                '<a href="#" class="side toggleComments"><span></span></a>',
                '<a href="#" class="name toggleComments">',
                    '{[this.renderCount(values.count)]}',
                '</a>',
            '</div>',
            {
                renderCount: this.renderCount
            }
        );

        var cls = this.type + '-' + this.className.replace(/\./g, '-');
        this.data = {
            id: this.memberId ? cls+"-"+this.memberId : cls,
            count: this.count
        };

        this.callParent(arguments);
    },

    renderCount: function(count) {
        if (count === 1) {
            return 'View 1 comment.';
        }
        else if (count > 1) {
            return 'View ' + count + ' comments.';
        }
        else {
            return 'No comments. Click to add.';
        }
    },

    afterRender: function() {
        this.callParent(arguments);
        this.getEl().on("click", this.toggle, this, {
            preventDefault: true,
            delegate: ".toggleComments"
        });
    },

    toggle: function() {
        this.expanded ? this.collapse() : this.expand();
    },

    expand: function() {
        this.expanded = true;
        var div = this.getEl().down(".comments-div");
        div.addCls('open');
        div.down('.name').setStyle("display", "none");

        var list = div.down('.comment-list');
        if (list) {
            list.setStyle('display', 'block');
        }
        else {
            this.loadComments(div);
        }
    },

    collapse: function() {
        this.expanded = false;
        var div = this.getEl().down(".comments-div");
        div.removeCls('open');
        div.down('.name').setStyle("display", "block");

        var list = div.down('.comment-list');
        if (list) {
            list.setStyle('display', 'none');
        }
    },

    loadComments: function(div) {
        this.list = new Docs.view.comments.List({
            renderTo: div
        });

        var target = [this.type, this.className, this.memberId];
        Docs.Comments.load(target, function(comments) {
            this.list.load(comments);
        }, this);
    },

    /**
     * Updates the comment count.
     * @param {Number} count
     */
    setCount: function(count) {
        this.getEl().down(".name").update(this.renderCount(count));
    }

});
