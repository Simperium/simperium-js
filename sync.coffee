class bucket
    constructor: (@s, @name, b_opts) ->
        @jd = @s.jd
        @options = @jd.deepCopy @s.options
        for own name, val of b_opts
            @options[name] = val
        @chan = @options['n']
        @space = "#{@options['app_id']}/#{@name}"
        @username = @options['username']
        @namespace = "#{@username}:#{@space}"
        @users = []
        @presence = null

        @clientid = null
        try
            @clientid = localStorage.getItem "#{@namespace}/clientid"
        catch error
            @clientid = null
        if not @clientid? or @clientid.indexOf("sjs") != 0
            @clientid = "sjs-#{@s.bversion}-#{@uuid(5)}"
            try
                localStorage.setItem "#{@namespace}/clientid"
            catch error
                console.log "#{@name}: couldnt set clientid"

        @cb_events = ['notify', 'notify_init', 'notify_version', 'local', 'get', 'ready', 'notify_pending', 'error', 'user_join', 'user_left']
        @cbs = {}
        @cb_e = @cb_l = @cb_ni = @cb_np = null
        @cb_n = @cb_nv = @cb_r = @cb_uj = @cb_ul = ->

        @initialized = false
        @authorized = false
        @data =
            last_cv: 0
            ccid: @uuid()
            store: {}
            send_queue: []
            send_queue_timer: null

        @started = false

        if not ('nostore' of @options)
            @_load_meta()
            @loaded = @_load_data()
            console.log "#{@name}: localstorage loaded #{@loaded} entities"
        else
            console.log "#{@name}: not loading from localstorage"
            @loaded = 0

        @_last_pending = null
        @_send_backoff = 15000
        @_backoff_max = 120000
        @_backoff_min = 15000

        console.log "#{@namespace}: bucket created: opts: #{JSON.stringify(@options)}"

    S4: ->
        (((1+Math.random())*0x10000)|0).toString(16).substring(1)

    uuid: (n) ->
        n = n || 8
        s = @S4()
        while n -= 1
            s += @S4()
        return s

    now: ->
        new Date().getTime()

    on: (event, callback) =>
        if event in @cb_events
            @cbs[event] = callback
            switch event
                when 'get', 'local'
                    @cb_l = callback
                when 'notify'
                    @cb_n = callback
                when 'notify_version'
                    @cb_nv = callback
                when 'notify_pending'
                    @cb_np = callback
                when 'notify_init'
                    @cb_ni = callback
                when 'ready'
                    @cb_r = callback
                when 'error'
                    @cb_e = callback
                when 'user_join'
                    @cb_uj = callback
                when 'user_left'
                    @cb_ul = callback
        else
            throw new Error("unsupported callback event")

    show_data: =>
        if not @s.supports_html5_storage()
            return
        total = 0
        for own key, datastr of localStorage
            console.log "[#{key}]: #{datastr}"
            total = total + 1
        console.log "#{total} total"

    _save_meta: ->
        if not @s.supports_html5_storage()
            return false
        console.log "#{@name}: save_meta ccid:#{@data.ccid} cv:#{@data.last_cv}"
        try
            localStorage.setItem "#{@namespace}/ccid", @data.ccid
            localStorage.setItem "#{@namespace}/last_cv", @data.last_cv
        catch error
            return false
        return true

    _load_meta: =>
        if not @s.supports_html5_storage()
            return
        @data.ccid = localStorage.getItem "#{@namespace}/ccid"
        @data.ccid ?= 1
        @data.last_cv = localStorage.getItem "#{@namespace}/last_cv"
        @data.last_cv ?= 0
        console.log "#{@name}: load_meta ccid:#{@data.ccid} cv:#{@data.last_cv}"

    _verify: (data) =>
        if !('object' of data) or !('version' of data)
            return false
        if @jd.entries(data['object']) == 0

            if @jd.entries(data['last']) > 0
                return true
            else
                return false
        else
            if !(data['version']?)
                return false
        return true

    _load_data: =>
        if not @s.supports_html5_storage()
            return
        prefix = "#{@namespace}/e/"
        p_len = prefix.length
        loaded = 0
        if localStorage.length == 0
            return 0
        for i in [0..localStorage.length-1]
            key = localStorage.key(i)
            if key? and key.substr(0, p_len) is prefix
                id = key.substr(p_len, key.length-p_len)
                try
                    data = JSON.parse localStorage.getItem key
                catch error
                    data = null
                if not data?
                    continue
                if @_verify data
                    data['check'] = null
                    @data.store[id] = data
                    loaded = loaded + 1
                else
                    console.log "ignoring CORRUPT data: #{JSON.stringify(data)}"
                    @_remove_entity id
        return loaded

    _save_entity: (id) =>
        if not @s.supports_html5_storage()
            return false
        key = "#{@namespace}/e/#{id}"
        store_data = @data.store[id]
        datastr = JSON.stringify(store_data)
        try
            localStorage.setItem key, datastr
        catch error
            return false
        ret_data = JSON.parse localStorage.getItem key
        if @jd.equals store_data, ret_data
#            console.log "saved #{key} len: #{datastr.length}"
            return true
        else
#            console.log "ERROR STORING ENTITY: store: #{JSON.stringify(store_data)}, retrieve: #{JSON.stringify(ret_data)}"
            return false

    _remove_entity: (id) =>
        if not @s.supports_html5_storage()
            return false
        key = "#{@namespace}/e/#{id}"
        try
            localStorage.removeItem key
        catch error
            return false
        return true

    _presence_change: (id, data, version, diff) =>
        console.log "#{@name}: notify for #{id} users: #{JSON.stringify(@users)}"
        if data is null
            if id in @users
                users = []
                users.push name for name in @users when name isnt id
                @users = users
                @cb_ul id
        else if id not in @users
                console.log "#{@name}: #{id} not found in users"
                @users.push id
                @cb_uj id

    get_users: =>
        @users

    start: =>
        console.log "#{@space}: started initialized: #{@initialized} authorized: #{@authorized}"
        @namespace = "#{@username}:#{@space}"
        @started = true
        @first = false
        if not @authorized
            if @s.connected
                @first = true
                if 'limit' of @options
                    index_query = "i:1:::#{@options['limit']}"
                else
                    index_query = "i:1:::40"
                @irequest_time = @now()
                @index_request = true
                @notify_index = {}
                opts =
                    app_id:  @options.app_id
                    token:  @options.token
                    name:   @name
                    clientid: @clientid
                    build: @s.bversion
                if not @initialized
                    opts.cmd = index_query
                @send("init:#{JSON.stringify(opts)}")
                console.log "#{@name}: sent init #{JSON.stringify(opts)} waiting for auth"
            else
                console.log "#{@name}: waiting for connect"
            return
        if not @initialized
            if not @first
                @notify_index = {}
                @_refresh_store()
        else
            console.log "#{@name}: retrieve changes from start"
            @retrieve_changes()

    on_data: (data) =>
        if data.substr(0, 5) == "auth:"
            user = data.substr(5)
            if user is "expired"
                console.log "auth expired"
                @started = false
                if @cb_e?
                    @cb_e "auth"
                return
            else
                @username = user
                @authorized = true
                if @initialized
                    @start()
        else if data.substr(0, 4) == "cv:?"
            console.log "#{@name}: cv out of sync, refreshing index"
            setTimeout => @_refresh_store()
        else if data.substr(0, 2) == "c:"
            changes = JSON.parse(data.substr(2))
            if @data.last_cv is "0" and changes.length is 0 and not @cv_check
                @cv_check = true
                @_refresh_store()
            @on_changes changes
        else if data.substr(0, 2) == "i:"
            console.log "#{@name}:  index msg received: #{@now() - @irequest_time}"
            @on_index_page JSON.parse(data.substr(2))
        else if data.substr(0, 2) == "e:"
            key_end = data.indexOf("\n")
            evkey = data.substr(2, key_end-2)
            version = evkey.substr(evkey.lastIndexOf('.')+1)
            key = evkey.substr(0, evkey.lastIndexOf('.'))
            entitydata = data.substr(key_end+1)
            if entitydata is "?"
                @on_entity_version null, key, version
            else
                entity = JSON.parse(entitydata)
                @on_entity_version entity['data'], key, version
        else if data.substr(0, 2) == "o:"
            opts = JSON.parse(data.substr(2))
            console.log "#{@name}: got options: #{JSON.stringify(opts)}"
            if @name.substr(0, 2) != "__" and 'shared' of opts and opts['shared'] is true
                console.log "#{@name}: is presence enabled"
                if not @presence
                    @presence = @s.bucket("__#{@name}__")
                    @presence.on('notify', @_presence_change)
                    @presence.start()
        else
            console.log "unknown message: #{data}"

    send: (message) =>
        console.log "sending: #{@chan}:#{message}"
        @s.send("#{@chan}:#{message}")

    _refresh_store: =>
        # load the index
        console.log "#{@name}: _refresh_store(): loading index"
        if 'limit' of @options
            index_query = "i:1:::#{@options['limit']}"
        else
            index_query = "i:1:::40"
        @send(index_query)
        @irequest_time = @now()
        @index_request = true
        return

    on_index_page: (response) =>
        now = @now()
        elapsed = now - @irequest_time
        console.log "#{@name}: index response time: #{elapsed}"
        console.log "#{@name}: on_index_page(): index page received, current= #{response['current']}"
        console.log response

        loaded = 0
        for item in response['index']
            @notify_index[item['id']] = false
            loaded++
            setTimeout do(item) =>
                => @on_entity_version(item['d'], item['id'], item['v'])

        if not ('mark' of response) or 'limit' of @options
            @index_request = false
            if 'current' of response
                @data.last_cv = response['current']
                @_save_meta()
            else
                @data.last_cv = 0
            if loaded is 0
                @_index_loaded()
        else
            @index_request = true
            console.log "#{@name}: index last process time: #{@now() - now}, page_delay: #{@options['page_delay']}"
            mark = response['mark']
            page_req = (mark) =>
                @send("i:1:#{mark}::100")
                @irequest_time = @now()

            setTimeout( (do(mark) =>
                => page_req(mark)), @options['page_delay'])

    on_index_error: =>
        console.log "#{@name}: index doesnt exist or other error"

    load_versions: (id, versions) =>
        if not (id of @data.store)
            return false
        min = Math.max(@data.store[id]['version'] - (versions+1), 1)
        for v in [min..@data.store[id]['version']-1]
            console.log "#{@name}: loading version #{id}.#{v}"
            @send("e:#{id}.#{v}")

    get_version: (id, version) =>
        evkey = "#{id}.#{version}"
        @send("e:#{evkey}")

    on_entity_version: (data, id, version) =>
        console.log "#{@name}: on_entity_version(#{data}, #{id}, #{version})"
        if data?
            data_copy = @jd.deepCopy(data)
        else
            data_copy = null
        if @initialized is false and @cb_ni?
            notify_cb = @cb_ni
        else
            notify_cb = @cb_n
        if id of @data.store and 'last' of @data.store[id] and @jd.entries(@data.store[id]['last'])
            data_copy = @jd.deepCopy(@data.store[id]['last'])

            notify_cb id, data_copy, null
            @notify_index[id] = true
            @_check_update(id)

        else if id of @data.store and version < @data.store[id]['version']
            @cb_nv id, data_copy, version
        else
            if not (id of @data.store)
                @data.store[id] = {}
            @data.store[id]['id'] = id
            @data.store[id]['object'] = data
            @data.store[id]['version'] = parseInt(version)

            notify_cb id, data_copy, version
            @notify_index[id] = true
            to_load = 0
            for own nid of @notify_index
                if @notify_index[nid] is false
                    to_load++
            if to_load is 0 and @index_request is false
                @_index_loaded()

    _index_loaded: =>
        console.log "#{@name}: index loaded, initialized: #{@initialized}"
        if @initialized is false
            @cb_r()
        @initialized = true
        console.log "#{@name}: retrieve changes from index loaded"
        @retrieve_changes()

    # id: id of object
    # new_object: latest server version of object (includes latest diff)
    # orig_object: the previous server version of object that the client had
    # diff: the newly received incoming diff (orig_object + diff = new_object)
    _notify_client: (key, new_object, orig_object, diff, version) =>
        console.log "#{@name}: _notify_client(#{key}, #{new_object}, #{orig_object}, #{JSON.stringify(diff)})"
        if not @cb_l?
            console.log "#{@name}: no get callback, notifying without transform"
            @cb_n key, new_object, version, diff
            return

        c_object = @cb_l key
        t_object = null
        t_diff = null
        cursor = null
        offsets = []

        if @jd.typeOf(c_object) is 'array'
            element = c_object[2]
            fieldname = c_object[1]
            c_object = c_object[0]
            cursor = @s._captureCursor element
            if cursor
                offsets[0] = cursor['startOffset']
                if 'endOffset' of cursor
                    offsets[1] = cursor['endOffset']

        if c_object? and orig_object?
#            console.log "going to do object diff new diff: #{JSON.stringify(diff)}"

            o_diff = @jd.object_diff orig_object, c_object
            console.log "client/server version diff: #{JSON.stringify(o_diff)}"
            if @jd.entries(o_diff) is 0
                console.log "local diff 0 entries"
                t_diff = diff
                t_object = orig_object
            else
                console.log "o_diff"
                console.log o_diff
                console.log "orig_object"
                console.log orig_object
                console.log "c_object"
                console.log c_object
                console.log "client modified doing transform"
                # client has local modifications, so we need to transform to apply new
                # changes to client's data
                # this transforms >o_diff< which is the local client modification with
                # respect to >diff< which is the new incoming change received from server
                # orig_object + diff = new_object
                # orig_object + o_diff (clients local modifications) = c_object (current
                # client data)
                # new client data (that includes both diffs) = orig_object + diff + T(o_diff)
                # new client data = (orig_object + diff) + T(o_diff)
                # new client data = new_object + T(o_diff)
                # new client data = new_object + t_diff
                t_diff = @jd.transform_object_diff o_diff, diff, orig_object
                t_object = new_object

            if cursor
                new_data = @jd.apply_object_diff_with_offsets t_object, t_diff, fieldname, offsets

                if element? and 'value' of element
                    element['value'] = new_data[fieldname]

                cursor['startOffset'] = offsets[0]
                if offsets.length > 1
                    cursor['endOffset'] = offsets[1]
                    if cursor['startOffset'] >= cursor['endOffset']
                        cursor['collapsed'] = true
                @s._restoreCursor element, cursor
            else
                console.log "in regular apply_object_diff"
                console.log "t_object"
                console.log t_object
                console.log "t_diff"
                console.log t_diff
                new_data = @jd.apply_object_diff t_object, t_diff
#                console.log "transformed diff: #{JSON.stringify(t_diff)}"
#            console.log "#{@name}: notifying client of new data for #{key}: #{JSON.stringify(new_data)}"
            @cb_n key, new_data, version, diff
        else if new_object
            @cb_n key, new_object, version, diff
        else
            @cb_n key, null, null, null

    _check_update: (id) =>
        console.log "#{@name}: _check_update(#{id})"
        if not (id of @data.store)
            return false
        s_data = @data.store[id]

        if s_data['change']
            found = false
            for change in @data.send_queue
                if change['id'] is s_data['change']['id'] and change['ccid'] is s_data['change']['ccid']
                    found = true
            if !found
                @_queue_change s_data['change']
                return true
            return false

        if s_data['check']?
            return false

        if s_data['last']? and @jd.entries(s_data['last']) > 0
            if @jd.equals s_data['object'], s_data['last']
                s_data['last'] = null
                @_remove_entity id
                return false

        change = @_make_change id
        if change?
            s_data['change'] = change
            @_queue_change change
        else
            @_remove_entity id
        return true

    update: (id, object) =>
        if arguments.length is 1 
            if @cb_l?
                object = @cb_l id
                if @jd.typeOf(object) is 'array'
                    object = object[0]
            else
                throw new Error("missing 'local' callback")
        console.log "#{@name}: update(#{id})"

        if not id? and not object?
            return false
        if id?
            if id.length is 0 or id.indexOf('/') isnt -1
                return false
        else
            id = @uuid()
        if not (id of @data.store)
            @data.store[id] =
                'id'        :   id
                'object'    :   {}
                'version'   :   null
                'change'    :   null
                'check'     :   null
        s_data = @data.store[id]
        s_data['last'] = @jd.deepCopy(object)
        s_data['modified'] = @s._time()
        @_save_entity id

        for change in @data.send_queue
            if String(id) is change['id']
                console.log "#{@name}: update(#{id}) found pending change, aborting"
                return null

        if s_data['check']?
            clearTimeout(s_data['check'])

        s_data['check'] = setTimeout((do(id, s_data) =>
            =>
                s_data['check'] = null
                s_data['change'] = @_make_change id
                s_data['last'] = null
                @_save_entity id
                @_queue_change s_data['change']
                ), @options['update_delay'])
        return id

        # create change objects
    _make_change: (id) =>
#        console.log "#{@name}: _make_change(#{id})"
        s_data = @data.store[id]

        change =
            'id'    :   String(id)
            'ccid'  :   @uuid()

        if not @initialized
            if s_data['last']?
                c_object = s_data['last']
            else
                return null
        else
            if @cb_l?
                c_object = @cb_l id
                if @jd.typeOf(c_object) is 'array'
                    c_object = c_object[0]
            else
                if s_data['last']?
                    c_object = s_data['last']
                else
                    return null

        if s_data['version']?
            change['sv'] = s_data['version']

        if c_object is null and s_data['version']?
            change['o'] = '-'
            console.log "#{@name}: deletion requested for #{id}"
        else if c_object? and s_data['object']?
            change['o'] = 'M'
            if 'sendfull' of s_data
                change['d'] = @jd.deepCopy c_object
                delete s_data['sendfull']
            else
                change['v'] = @jd.object_diff s_data['object'], c_object
                if @jd.entries(change['v']) is 0
                    change = null
        else
            change = null
#        console.log "_make_change(#{id}) returning: #{JSON.stringify(change)}"
        return change

    _queue_change: (change) =>
        if not change?
            return

        console.log "_queue_change(#{change['id']}:#{change['ccid']}): sending"
        @data.send_queue.push change
        @send("c:#{JSON.stringify(change)}")
        @_check_pending()

        if @data.send_queue_timer?
            clearTimeout(@data.send_queue_timer)

        @data.send_queue_timer = setTimeout @_send_changes, @_send_backoff

    _send_changes: =>
        if @data.send_queue.length is 0
            console.log "#{@name}: send_queue empty, done"
            @data.send_queue_timer = null
            return
        if not @s.connected
            console.log "#{@name}: _send_changes: not connected"
        else
            for change in @data.send_queue
                console.log "#{@name}: sending change: #{JSON.stringify(change)}"
                @send("c:#{JSON.stringify(change)}")

        @_send_backoff = @_send_backoff * 2
        if @_send_backoff > @_backoff_max
            @_send_backoff = @_backoff_max

        @data.send_queue_timer = setTimeout @_send_changes, @_send_backoff

    retrieve_changes: =>
        console.log "#{@name}: requesting changes since cv:#{@data.last_cv}"
        @send("cv:#{@data.last_cv}")
#        @sio.send("cv:#{@data.last_cv}")
        return

    on_changes: (response) =>
        check_updates = []
        reload_needed = false
        @_send_backoff = @_backoff_min
        console.log "#{@name}: on_changes(): response="
        console.log response
        for change in response
            id = change['id']
            console.log "#{@name}: processing id=#{id}"
            pending_to_delete = []
            for pending in @data.send_queue
                if change['clientid'] is @clientid and id is pending['id']
#                    console.log "#{@name}: deleting change for id #{id}"
                    change['local'] = true
                    pending_to_delete.push pending
                    check_updates.push id
            for pd in pending_to_delete
                @data.store[pd['id']]['change'] = null
                @_save_entity pd['id']
                @data.send_queue = (p for p in @data.send_queue when p isnt pd)
            if pending_to_delete.length > 0
                @_check_pending()
#            console.log "#{@name}: send queue: #{JSON.stringify(@data.send_queue)}"

            if 'error' of change
                switch change['error']
                    when 412
                        console.log "#{@name}: on_changes(): empty change, dont check"
                        idx = check_updates.indexOf(change['id'])
                        if idx > -1
                            check_updates.splice(idx, 1)
                    when 409
                        console.log "#{@name}: on_changes(): duplicate change, ignoring"
                    when 405
                        console.log "#{@name}: on_changes(): bad version"
                        if change['id'] of @data.store
                            @data.store[change['id']]['version'] = null
                        reload_needed = true
                    when 440
                        console.log "#{@name}: on_change(): bad diff, sending full object"
                        @data.store[id]['sendfull'] = true
                    else
                        console.log "#{@name}: error for last change, reloading"
                        if change['id'] of @data.store
                            @data.store[change['id']]['version'] = null
                        reload_needed = true
            else
                op = change['o']
                if op is '-'
                    delete @data.store[id]
                    @_remove_entity id
                    if not ('local' of change)
#                        setTimeout do(change) =>
#                            => @_notify_client change['id'], null, null, null
                        @_notify_client change['id'], null, null, null, null

                else if op is 'M'
                    s_data = @data.store[id]
                    if ('sv' of change and s_data? and s_data['version']? and s_data['version'] == change['sv']) or !('sv' of change) or (change['ev'] == 1)
                        if not s_data?
                            @data.store[id] =
                                'id'        :   id
                                'object'    :   {}
                                'version'   :   null
                                'last'      :   null
                                'change'    :   null
                                'check'     :   null
                            s_data = @data.store[id]
#                        console.log "#{@name}: processing modify for #{JSON.stringify(s_data)}"
                        orig_object = @jd.deepCopy s_data['object']
                        s_data['object'] = @jd.apply_object_diff s_data['object'], change['v']
                        s_data['version'] = change['ev']

                        new_object = @jd.deepCopy s_data['object']

                        if not ('local' of change)
#                            setTimeout do(change, new_object, orig_object) =>
#                                => @_notify_client change['id'], new_object, orig_object, change['v']
                            @_notify_client change['id'], new_object, orig_object, change['v'], change['ev']
                    else if s_data? and s_data['version']? and change['ev'] <= s_data['version']
                        console.log "#{@name}: old or duplicate change received, ignoring, change.ev=#{change['ev']}, s_data.version:#{s_data['version']}"
                    else
                        if s_data?
                            console.log "#{@name}: version mismatch couldnt apply change, change.ev:#{change['ev']}, s_data.version:#{s_data['version']}"
                        else
                            console.log "#{@name}: version mismatch couldnt apply change, change.ev:#{change['ev']}, s_data null"
                        if s_data?
                            @data.store[id]['version'] = null
                        reload_needed = true
                else
                    console.log "#{@name}: no operation found for change"
                if not reload_needed
                    @data.last_cv = change['cv']
                    @_save_meta()
                    console.log "#{@name}: checkpoint cv=#{@data.last_cv} ccid=#{@data.ccid}"
        if reload_needed
            console.log "#{@name}: reload needed, refreshing store"
            setTimeout => @_refresh_store()
        else
            for id in check_updates
                do (id) => setTimeout (=> @_check_update id), @options['update_delay']
        return

    pending: =>
        x = (change['id'] for change in @data.send_queue)
        console.log "#{@name}: pending: #{JSON.stringify(x)}"
        (change['id'] for change in @data.send_queue)

    _check_pending: =>
        if @cb_np?
            curr_pending = @pending()
            diff = true
            if @_last_pending
                diff = false
                if @_last_pending.length is curr_pending.length
                    for x in @_last_pending
                        if curr_pending.indexOf(x) is -1
                            diff = true
                else
                    diff = true
            if diff
                @_last_pending = curr_pending
                @cb_np curr_pending


class simperium
    lowerstrip: (s) ->
        s = s.toLowerCase()
        if String::trim? then s.trim() else s.replace /^\s+|\s+$/g, ""

    _time: ->
        d = new Date()
        Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds(), d.getUTCMilliseconds())/1000

    supports_html5_storage: ->
        try
            return 'localStorage' of window && window['localStorage'] != null
        catch error
            return false

    constructor: (@app_id, @options) ->
        @bversion = 2013070403
        @jd = new jsondiff()
        @dmp = jsondiff.dmp
        @auth_token = null
        @options = @options || {}

        @options['app_id'] = @app_id
        @sock_opts = { 'debug' : false }
        if 'sockjs' of @options
            for own name, val of @options['sockjs']
                @sock_opts[name] = val

        if not ('host' of @options) then @options['host'] = 'api.simperium.com'
        if @options['host'].indexOf("simperium.com") != -1 and not ('port' of @options)
            scheme = "https"
        else
            scheme = "http"

        if not ('port' of @options) then @options['port'] = 80
        if 'token' of @options then @auth_token = @options['token']

        @buckets = {}
        @channels = 0

        if not ('update_delay' of @options)
            @options['update_delay'] = 0
        if not ('page_delay' of @options)
            @options['page_delay'] = 0

        @options['prefix'] = "sock/1/#{@appid}"

        @options['port'] = parseInt(@options['port'])
        if @options['port'] != 80 and @options['port'] != 443
            @sock_url = "#{scheme}://#{@options['host']}:#{@options['port']}/#{@options['prefix']}"
        else
            @sock_url = "#{scheme}://#{@options['host']}/#{@options['prefix']}"

        @stopped = false
        @_sock_backoff = 3000
        @_sock_hb = 1
        @_sock_connect()

    bucket: (name, b_opts) =>
        name = @lowerstrip(name)
        b_opts = b_opts || {}
        b_opts['n'] = @channels++
        b = new bucket(@, name, b_opts)
        @buckets[b_opts['n']] = b
        return b

    on: (bucket, event, callback) =>
        @buckets[bucket].on(event, callback)

    start: =>
        @stopped = false
        for own name, bucket of @buckets
            bucket.start()

    stop: =>
        @stopped = true
        if @sock?
            @sock.close()

    send: (data) =>
        @sock.send(data)

    synced: =>
        for own name, bucket of @buckets
            if bucket.pending().length > 0
                return false
        return true

    _sock_connect: =>
        console.log "simperium: connecting to #{@sock_url}"
        @connected = false
        @authorized = false
        @sock = new SockJS(@sock_url, undefined, @sock_opts)
        @sock.onopen = @_sock_opened
        @sock.onmessage = @_sock_message
        @sock.onclose = @_sock_closed

    _sock_opened: =>
        @_sock_backoff = 3000
        @connected = true
        @_sock_hb_timer = setTimeout @_sock_hb_check, 20000
        for own name, bucket of @buckets
            if bucket.started
                bucket.start()

    _sock_closed: =>
        @connected = false
        for own name, bucket of @buckets
            bucket.authorized = false
        console.log "simperium: sock js closed"
        if @_sock_backoff < 4000
            @_sock_backoff = @_sock_backoff + 1
        else
            @_sock_backoff = 15000
        if @_sock_hb_timer
            clearTimeout @_sock_hb_timer
            @_sock_hb_timer = null
        if not @stopped
            setTimeout @_sock_connect, @_sock_backoff

    _sock_hb_check: =>
        delay = new Date().getTime() - @_sock_msg_time
        if @connected is false
            return
        if delay > 40000
            console.log "simperium: force conn close"
            @sock.close()
        else if delay > 15000
            console.log "simperium: send hb #{@_sock_hb}"
            @sock.send("h:#{@_sock_hb}")
        @_sock_hb_timer = setTimeout @_sock_hb_check, 20000

    _sock_message: (e) =>
        @_sock_msg_time = new Date().getTime()
        data = e.data
        sep = data.indexOf(":")
        chan = null
        if sep is 1 and data.charAt(0) is 'h'
            @_sock_hb = data.substr(2)
            return
        try
            chan = parseInt(data.substr(0, sep))
            data = data.substr(sep+1)
        catch error
            chan = null
        if chan is null
            return
        if not (chan of @buckets)
            return
        @buckets[chan].on_data(data)

    _captureCursor: (element) =>
        return
    _captureCursor: `function(element) {
        if ('activeElement' in element && !element.activeElement) {
            // Safari specific code.
            // Restoring a cursor in an unfocused element causes the focus to jump.
            return null;
        }
        var padLength = this.dmp.Match_MaxBits / 2;    // Normally 16.
        var text = element.value;
        var cursor = {};
        if ('selectionStart' in element) {    // W3
            try {
                var selectionStart = element.selectionStart;
                var selectionEnd = element.selectionEnd;
            } catch (e) {
                // No cursor; the element may be "display:none".
                return null;
            }
            cursor.startPrefix = text.substring(selectionStart - padLength, selectionStart);
            cursor.startSuffix = text.substring(selectionStart, selectionStart + padLength);
            cursor.startOffset = selectionStart;
            cursor.collapsed = (selectionStart == selectionEnd);
            if (!cursor.collapsed) {
                cursor.endPrefix = text.substring(selectionEnd - padLength, selectionEnd);
                cursor.endSuffix = text.substring(selectionEnd, selectionEnd + padLength);
                cursor.endOffset = selectionEnd;
            }
        } else {    // IE
            // Walk up the tree looking for this textarea's document node.
            var doc = element;
            while (doc.parentNode) {
                doc = doc.parentNode;
            }
            if (!doc.selection || !doc.selection.createRange) {
                // Not IE?
                return null;
            }
            var range = doc.selection.createRange();
            if (range.parentElement() != element) {
                // Cursor not in this textarea.
                return null;
            }
            var newRange = doc.body.createTextRange();

            cursor.collapsed = (range.text == '');
            newRange.moveToElementText(element);
            if (!cursor.collapsed) {
                newRange.setEndPoint('EndToEnd', range);
                cursor.endPrefix = newRange.text;
                cursor.endOffset = cursor.endPrefix.length;
                cursor.endPrefix = cursor.endPrefix.substring(cursor.endPrefix.length - padLength);
            }
            newRange.setEndPoint('EndToStart', range);
            cursor.startPrefix = newRange.text;
            cursor.startOffset = cursor.startPrefix.length;
            cursor.startPrefix = cursor.startPrefix.substring(cursor.startPrefix.length - padLength);

            newRange.moveToElementText(element);
            newRange.setEndPoint('StartToStart', range);
            cursor.startSuffix = newRange.text.substring(0, padLength);
            if (!cursor.collapsed) {
                newRange.setEndPoint('StartToEnd', range);
                cursor.endSuffix = newRange.text.substring(0, padLength);
            }
        }

        // Record scrollbar locations
        if ('scrollTop' in element) {
            cursor.scrollTop = element.scrollTop / element.scrollHeight;
            cursor.scrollLeft = element.scrollLeft / element.scrollWidth;
        }

        // alert(cursor.startPrefix + '|' + cursor.startSuffix + ' ' +
        //         cursor.startOffset + '\n' + cursor.endPrefix + '|' +
        //         cursor.endSuffix + ' ' + cursor.endOffset + '\n' +
        //         cursor.scrollTop + ' x ' + cursor.scrollLeft);
        return cursor;
    }`

    _restoreCursor: (element, cursor) =>
        return
    _restoreCursor: `function(element, cursor) {
        // Set some constants which tweak the matching behaviour.
        // Maximum distance to search from expected location.
        this.dmp.Match_Distance = 1000;
        // At what point is no match declared (0.0 = perfection, 1.0 = very loose)
        this.dmp.Match_Threshold = 0.9;

        var padLength = this.dmp.Match_MaxBits / 2;    // Normally 16.
        var newText = element.value;

        // Find the start of the selection in the new text.
        var pattern1 = cursor.startPrefix + cursor.startSuffix;
        var pattern2, diff;
        var cursorStartPoint = this.dmp.match_main(newText, pattern1,
                cursor.startOffset - padLength);
        if (cursorStartPoint !== null) {
            pattern2 = newText.substring(cursorStartPoint,
                                                                     cursorStartPoint + pattern1.length);
            //alert(pattern1 + '\nvs\n' + pattern2);
            // Run a diff to get a framework of equivalent indicies.
            diff = this.dmp.diff_main(pattern1, pattern2, false);
            cursorStartPoint += this.dmp.diff_xIndex(diff, cursor.startPrefix.length);
        }

        var cursorEndPoint = null;
        if (!cursor.collapsed) {
            // Find the end of the selection in the new text.
            pattern1 = cursor.endPrefix + cursor.endSuffix;
            cursorEndPoint = this.dmp.match_main(newText, pattern1,
                    cursor.endOffset - padLength);
            if (cursorEndPoint !== null) {
                pattern2 = newText.substring(cursorEndPoint,
                                                                         cursorEndPoint + pattern1.length);
                //alert(pattern1 + '\nvs\n' + pattern2);
                // Run a diff to get a framework of equivalent indicies.
                diff = this.dmp.diff_main(pattern1, pattern2, false);
                cursorEndPoint += this.dmp.diff_xIndex(diff, cursor.endPrefix.length);
            }
        }

        // Deal with loose ends
        if (cursorStartPoint === null && cursorEndPoint !== null) {
            // Lost the start point of the selection, but we have the end point.
            // Collapse to end point.
            cursorStartPoint = cursorEndPoint;
        } else if (cursorStartPoint === null && cursorEndPoint === null) {
            // Lost both start and end points.
            // Jump to the offset of start.
            cursorStartPoint = cursor.startOffset;
        }
        if (cursorEndPoint === null) {
            // End not known, collapse to start.
            cursorEndPoint = cursorStartPoint;
        }

        // Restore selection.
        if ('selectionStart' in element) {    // W3
            element.selectionStart = cursorStartPoint;
            element.selectionEnd = cursorEndPoint;
        } else {    // IE
            // Walk up the tree looking for this textarea's document node.
            var doc = element;
            while (doc.parentNode) {
                doc = doc.parentNode;
            }
            if (!doc.selection || !doc.selection.createRange) {
                // Not IE?
                return;
            }
            // IE's TextRange.move functions treat '\r\n' as one character.
            var snippet = element.value.substring(0, cursorStartPoint);
            var ieStartPoint = snippet.replace(/\r\n/g, '\n').length;

            var newRange = doc.body.createTextRange();
            newRange.moveToElementText(element);
            newRange.collapse(true);
            newRange.moveStart('character', ieStartPoint);
            if (!cursor.collapsed) {
                snippet = element.value.substring(cursorStartPoint, cursorEndPoint);
                var ieMidLength = snippet.replace(/\r\n/g, '\n').length;
                newRange.moveEnd('character', ieMidLength);
            }
            newRange.select();
        }

        // Restore scrollbar locations
        if ('scrollTop' in cursor) {
            element.scrollTop = cursor.scrollTop * element.scrollHeight;
            element.scrollLeft = cursor.scrollLeft * element.scrollWidth;
        }
    }`


window['Simperium'] = simperium
bucket.prototype['on'] = bucket.prototype.on
bucket.prototype['start'] = bucket.prototype.start
bucket.prototype['load_versions'] = bucket.prototype.load_versions
bucket.prototype['pending'] = bucket.prototype.pending
simperium.prototype['on'] = simperium.prototype.on
simperium.prototype['start'] = simperium.prototype.start
simperium.prototype['bucket'] = simperium.prototype.bucket
simperium.prototype['synced'] = simperium.prototype.synced
