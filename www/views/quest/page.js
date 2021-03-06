define([
    'underscore',
    'views/proto/common',
    'views/quest/big', 'views/comment/collection',
    'models/comment-collection',
    'text!templates/quest-page.html'
], function (_, Common, QuestBig, CommentCollection, CommentCollectionModel, html) {
    return Common.extend({

        activated: false,

        template: _.template(html),

        subviews: {
            '.quest-big': function () {
                return new QuestBig({
                    model: this.model
                });
            },
            '.comments': function () {
                var commentsModel = new CommentCollectionModel([], { 'quest_id': this.model.id });
                commentsModel.fetch();
                return new CommentCollection({
                    collection: commentsModel
                });
            },
        },

        serialize: function () {
            return this.model.serialize();
        },

        afterInitialize: function () {
            this.listenTo(this.model, 'change', this.render);
        }
    });
});
