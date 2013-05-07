# Aulë
#
# A web interface to the Varda database for genomic variation frequencies.
#
# Martijn Vermaat <m.vermaat.hg@lumc.nl>
#
# Licensed under the MIT license, see the LICENSE file.


define ['jquery', 'jquery.base64'], ($) ->

    # Accepted server API versions.
    ACCEPT_VERSION = '>=0.2.0,<0.3.0'

    # Create HTTP Basic Authentication header value.
    makeBasicAuth = (login, password) ->
        'Basic ' + $.base64.encode (login + ':' + password)

    # Add HTTP Basic Authentication header to request.
    addAuth = (r, login, password) ->
        if login
            r.setRequestHeader 'Authorization', makeBasicAuth login, password

    # Add Accept-Version header to request.
    addVersion = (r) ->
        r.setRequestHeader 'Accept-Version', ACCEPT_VERSION

    # Add Range header to request for collection resources.
    addRangeForPage = (page, page_size=50) ->
        start = page * page_size
        end = start + page_size - 1
        (r) -> r.setRequestHeader 'Range', "items=#{ start }-#{ end }"

    # Normalize ajax error handling.
    ajaxError = (handler) ->
        (xhr) ->
            try
                error = ($.parseJSON xhr.responseText).error
            catch e
                error =
                    code: 'response_error',
                    message: "Unable to parse server response (status: #{xhr.status} #{xhr.statusText})"
                console.log 'Unable to parse server response'
                console.log xhr.responseText
            handler? error.code, error.message

    class Api
        constructor: (@root) ->

        init: ({success, error}) =>
            @request @root,
                error: -> error? 'connection_error', 'Could not connect to server'
                success: (r) =>
                    if r.status != 'ok'
                        error? 'response_error', 'Unexpected response from server'
                        return
                    @uris =
                        root: @root
                        authentication: r.authentication.uri
                        genome: r.genome.uri
                        annotations: r.annotation_collection.uri
                        coverages: r.coverage_collection.uri
                        data_sources: r.data_source_collection.uri
                        samples: r.sample_collection.uri
                        users: r.user_collection.uri
                        variants: r.variant_collection.uri
                        variations: r.variation_collection.uri
                    success?()

        authenticate: (@login, @password, {success, error}) =>
            @current_user = null
            @request @uris.authentication,
                success: (r) =>
                    if r.authenticated
                        @current_user = r.user
                        success?()
                    else
                        error? 'authentication_error',
                            "Unable to authenticate with login '#{login}' and password '***'"
                error: error

        coverages: (options={}) =>
            uri = @uris.coverages + '?embed=data_source'
            if options.sample?
                uri += "&sample=#{ encodeURIComponent options.sample }"
            @collection uri, options

        data_source: (uri, options={}) =>
            success = options.success
            options.success = (data) -> success? data.data_source
            @request uri, options

        data_sources: (options={}) =>
            uri = @uris.data_sources
            if options.filter == 'own'
                uri += "?user=#{ encodeURIComponent @current_user?.uri }"
            @collection uri, options

        sample: (uri, options={}) =>
            success = options.success
            options.success = (data) -> success? data.sample
            @request uri, options

        samples: (options={}) =>
            uri = @uris.samples
            if options.filter == 'own'
                uri += "?user=#{ encodeURIComponent @current_user?.uri }"
            if options.filter == 'public'
                uri += '?public=true'
            @collection uri, options

        user: (uri, options={}) =>
            success = options.success
            options.success = (data) -> success? data.user
            @request uri, options

        users: (options={}) =>
            @collection @uris.users, options

        variations: (options={}) =>
            uri = @uris.variations + '?embed=data_source'
            if options.sample?
                uri += "&sample=#{ encodeURIComponent options.sample }"
            @collection uri, options

        variant: (uri, options={}) =>
            success = options.success
            options.success = (data) -> success? data.variant
            @request uri, options

        create_variant: (options={}) =>
            success = options.success
            options.success = (data) -> success? data.variant
            options.method = 'POST'
            @request @uris.variants, options

        collection: (uri, options={}) =>
            options.page_number ?= 0
            options.page_size ?= 50
            @request uri,
                beforeSend: addRangeForPage options.page_number
                success: (data, status, xhr) ->
                    range = xhr.getResponseHeader 'Content-Range'
                    total = parseInt (range.split '/')[1]
                    pagination =
                        total: Math.ceil total / options.page_size
                        current: options.page_number
                    options.success? data.collection.items, pagination
                error: (code, message) ->
                    if code == 'unsatisfiable_range'
                        options.success? [], total: 0, current: 0
                    else
                        options.error? code, message

        request: (uri, options={}) =>
            $.ajax uri,
                beforeSend: (r) =>
                    addAuth r, @login, @password
                    addVersion r
                    options.beforeSend? r
                data: options.data
                success: options.success
                error: ajaxError options.error
                dataType: 'json'
                type: options.method ? 'GET'
            return
