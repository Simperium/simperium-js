(function (factory) {
    if (typeof define === 'function' && define.amd) {
        // AMD. Register as an anonymous module.
        define('backbone-simperium', ['backbone'], factory);
    } else {
        // Browser globals
        factory(Backbone);
    }
}(function( Backbone ) {
		Backbone.SimperiumModel = Backbone.Model.extend({
			initialize: function(attributes, options) {
				_.bindAll(this, "remote_update", "local_data");
				this.bucket = options.bucket;
				this.id = options.id;
				this.bucket.on('notify', this.remote_update);
				this.bucket.on('local', this.local_data);
				this.bucket.start();
			},

			remote_update: function(id, data, version) {
				if (id != this.id) return;
				if (data == null) {
					this.clear();
				} else {
					this.set(data);
					this.version = version;
				}
			},

			local_data: function(id) {
				if (id != this.id) return;

				return this.toJSON();
			},
		});

		Backbone.SimperiumCollection = Backbone.Collection.extend({
			initialize: function(models, options) {
				_.bindAll(this, "remote_update", "local_data");
				this.bucket = options.bucket;
				this.bucket.on('notify', this.remote_update);
				this.bucket.on('local', this.local_data);
				this.bucket.start();
			},

			remote_update: function(id, data, version) {
				 var model = this.get(id);
				 if (data == null) {
					 if (model) {
						 model.destroy();
					 }
				 } else {
					 if (model) {
						 model.version = version;
						 model.set(data);
					 } else {
						 model = new this.model(data);
						 model.id = id;
						 model.version = version;
						 this.add(model);
					 }
				 }
			},

			local_data: function(id) {
				var model = this.get(id);
				if (model) {
					return model.toJSON();
				}
				return null;
			},
		});

		Backbone.sync = function(method, model, options) {
			if (!model) return;
			var S4 = function() {
				return (((1 + Math.random()) * 0x10000) | 0).toString(16).substring(1);
			};

			var bucket = model.collection && model.collection.bucket || model.bucket;
			if (!bucket) return;

			var isModel = !(typeof model.isNew === 'undefined');
			if (isModel) {
				if (model.isNew()) {
					model.id = S4()+S4()+S4()+S4()+S4();
					if (model.collection) {
						model.trigger("change:id", model, model.collection, {});
					}
				}

				switch (method) {
					case "create"   :
					case "update"   : bucket.update(model.id, model.toJSON()); options && options.success(); break;
					case "delete"   : bucket.update(model.id, null); options && options.success(); break;
				}
			}
		};

		return Backbone;
	}
));
