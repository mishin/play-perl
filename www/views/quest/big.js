define([
    'underscore',
    'backbone',
    'views/proto/common',
    'views/like',
    'views/quest/completed',
    'models/current-user',
    'bootbox',
    'text!templates/quest-big.html'
], function (_, Backbone, Common, Like, QuestCompleted, currentUser, bootbox, html) {
    'use strict';
    return Common.extend({
        template: _.template(html),

        events: {
            "click .quest-close": "close",
            "click .quest-abandon": "abandon",
            "click .quest-leave": "leave",
            "click .quest-join": "join",
            "click .quest-resurrect": "resurrect",
            "click .quest-reopen": "reopen",
            "click .delete": "destroy",
            "click .edit": "startEdit",
            "keyup input": "edit"
        },

        subviews: {
            '.likes': function () {
                return new Like({ model: this.model });
            }
        },

        afterInitialize: function () {
            this.listenTo(this.model, 'change', this.render);
        },

        close: function () {
            this.model.close();
            var modal = new QuestCompleted({ model: this.model });
            modal.start();
        },

        abandon: function () {
            this.model.abandon();
        },

        leave: function () {
            this.model.leave();
        },

        join: function () {
            this.model.join();
        },

        resurrect: function () {
            this.model.resurrect();
        },

        reopen: function () {
            this.model.reopen();
        },

        startEdit: function () {
            if (!this.isOwned()) {
                return;
            }
            this.$('.quest-edit').show();
            this.$('.quest-big-labels .quest-big-tags-edit').show();

            this.backup = _.clone(this.model.attributes);

            var tags = this.model.get('tags') || [];
            this.$('.quest-big-tags-input').val(tags.join(', '));
            this.$('.quest-edit').val(this.model.get('name'));
            this.validateForm();

            this.$('.quest-title').hide();
            this.$('.quest-tags').hide();
            this.$('.quest-edit').focus();
        },

        // check if edit form is valid, and also highlight invalid fiels appropriately
        validateForm: function () {
            var ok = true;
            if (this.$('.quest-edit').val().length) {
                this.$('.quest-edit').parent().removeClass('error');
            }
            else {
                this.$('.quest-edit').parent().addClass('error');
                ok = false;
            }

              var cg = this.$('.quest-big-tags-input').parent(); // control-group
            if (this.model.validateTagline(cg.find('input').val())) {
                cg.removeClass('error');
                cg.find('input').tooltip('hide');
            }
            else {
                if (!cg.hasClass('error')) {
                    cg.addClass('error');

                    // copy-pasted from views/quest/add, TODO - refactor
                    var oldFocus = $(':focus');
                    cg.find('input').tooltip('show');
                    $(oldFocus).focus();
                }
                ok = false;
            }
            return ok;
        },

        edit: function (e) {
            if (this.validateForm() && e.which == 13) {
                this.closeEdit(true);
            }
            else if (e.which == 27) {
                this.closeEdit(false);
            }
        },

        closeEdit: function(save) {

            if (save) {
                // form is validated already by edit() method
                var value = this.$('.quest-edit').val();
                var tagline = this.$('.quest-big-tags-input').val();

                this.model.save({
                    name: value,
                    tags: this.model.tagline2tags(tagline)
                });
            }

            this.$('.quest-edit').hide();
            this.$('.quest-big-labels .quest-big-tags-edit').hide();
            this.$('.quest-title').show();
            this.$('.quest-tags').show();
        },

        destroy: function () {
            var that = this;
            bootbox.confirm("Quest and all comments will be destroyed permanently. Are you sure?", function(result) {
                if (result) {
                    that.model.destroy({
                        success: function(model, response) {
                            Backbone.trigger('pp:navigate', '/', { trigger: true });
                        },
                    });
                }
            });
        },

        isOwned: function () {
            return (currentUser.get('login') == this.model.get('user'));
        },

        serialize: function () {
            var params = this.model.serialize();
            // TODO - should we move this to model?
            params.currentUser = currentUser.get('login');
            params.my = this.isOwned();
            if (!params.likes) {
                params.likes = [];
            }
            return params;
        },
    });
});
