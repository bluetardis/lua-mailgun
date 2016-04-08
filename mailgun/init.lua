local ltn12 = require("ltn12")
local encode_base64, encode_query_string, parse_query_string
do
  local _obj_0 = require("mailgun.util")
  encode_base64, encode_query_string, parse_query_string = _obj_0.encode_base64, _obj_0.encode_query_string, _obj_0.parse_query_string
end
local concat
concat = table.concat
local json = require("cjson")
local add_recipients
add_recipients = function(data, field, emails)
  if not (emails) then
    return 
  end
  if type(emails) == "table" then
    for _index_0 = 1, #emails do
      local email = emails[_index_0]
      table.insert(data, {
        field,
        email
      })
    end
  else
    data[field] = emails
  end
end
local items_method
items_method = function(path, items_field, paging_field)
  if items_field == nil then
    items_field = "items"
  end
  if paging_field == nil then
    paging_field = "paging"
  end
  return function(self, opts)
    if opts == nil then
      opts = { }
    end
    local res, err = self:api_request(tostring(path) .. "?" .. tostring(encode_query_string(opts)))
    if res then
      return res[items_field], res[paging_field]
    else
      return nil, err
    end
  end
end
local Mailgun
do
  local _class_0
  local _base_0 = {
    api_path = "https://api.mailgun.net/v3/",
    for_domain = function(self, domain)
      return Mailgun({
        domain = domain,
        api_key = self.api_key,
        http = self.http_provider
      })
    end,
    http = function(self)
      if not (self._http) then
        self.http_provider = self.http_provider or (function()
          if ngx then
            return "lapis.nginx.http"
          else
            return "ssl.https"
          end
        end)()
        if type(self.http_provider) == "function" then
          self._http = self:http_provider()
        else
          self._http = require(self.http_provider)
        end
      end
      return self._http
    end,
    api_request = function(self, path, data, domain)
      if domain == nil then
        domain = self.domain
      end
      local prefix = tostring(self.api_path) .. tostring(domain)
      local body = data and encode_query_string(data)
      local out = { }
      local req = {
        url = prefix .. path,
        source = body and ltn12.source.string(body) or nil,
        method = data and "POST" or "GET",
        headers = {
          ["Host"] = "api.mailgun.net",
          ["Content-type"] = body and "application/x-www-form-urlencoded" or nil,
          ["Content-length"] = body and #body or nil,
          ["Authorization"] = "Basic " .. encode_base64(self.api_key)
        },
        sink = ltn12.sink.table(out),
        protocol = not ngx and "sslv23" or nil
      }
      local _, status = self:http().request(req)
      return self:format_response(concat(out), status)
    end,
    format_response = function(self, res, status)
      pcall(function()
        res = json.decode(res)
      end)
      if res == "" or not res then
        res = "invalid response"
      end
      if status ~= 200 then
        return nil, res.message or res
      end
      return res
    end,
    send_email = function(self, opts)
      if opts == nil then
        opts = { }
      end
      local to, subject, body, domain
      to, subject, body, domain = opts.to, opts.subject, opts.body, opts.domain
      assert(to, "missing recipients")
      assert(subject, "missing subject")
      assert(body, "missing body")
      domain = domain or self.domain
      local data = {
        from = opts.from or self.default_sender,
        subject = subject,
        [opts.html and "html" or "text"] = body
      }
      add_recipients(data, "to", to)
      add_recipients(data, "cc", opts.cc)
      add_recipients(data, "bcc", opts.bcc)
      if opts.tags then
        local _list_0 = opts.tags
        for _index_0 = 1, #_list_0 do
          local t = _list_0[_index_0]
          table.insert(data, {
            "o:tag",
            t
          })
        end
      end
      if opts.vars then
        data["recipient-variables"] = json.encode(opts.vars)
      end
      if opts.headers then
        for h, v in pairs(opts.headers) do
          data["h:" .. tostring(h)] = v
        end
      end
      if opts.track_opens then
        data["o:tracking-opens"] = "yes"
      end
      do
        local c = opts.campaign
        if c then
          data["o:campaign"] = c
        end
      end
      return self:api_request("/messages", data, domain)
    end,
    create_campaign = function(self, name)
      local res, err = self:api_request("/campaigns", {
        name = name
      })
      if res then
        return res.campaign
      else
        return res, err
      end
    end,
    get_campaigns = function(self)
      local res, err = self:api_request("/campaigns")
      if res then
        return res.items, res
      else
        return res, err
      end
    end,
    get_messages = function(self)
      local params = encode_query_string({
        event = "stored"
      })
      local res, err = self:api_request("/events?" .. tostring(params))
      if res then
        return res.items, res.paging
      else
        return nil, err
      end
    end,
    get_unsubscribes = items_method("/unsubscribes"),
    each_unsubscribe = function(self)
      return self:_each_item(self.get_unsubscribes, "address")
    end,
    get_bounces = items_method("/bounces"),
    each_bounce = function(self)
      return self:_each_item(self.get_bounces, "address")
    end,
    get_complaints = items_method("/complaints"),
    each_complaint = function(self)
      return self:_each_item(self.get_complaints, "address")
    end,
    _each_item = function(self, getter, paging_field)
      local parse_url = require("socket.url").parse
      local after_value
      return coroutine.wrap(function()
        while true do
          local opts = {
            limit = 1000,
            page = after_value and "next",
            [paging_field] = after_value
          }
          local page, paging = getter(self, opts)
          if not (page) then
            return 
          end
          if not (next(page)) then
            return 
          end
          for _index_0 = 1, #page do
            local item = page[_index_0]
            coroutine.yield(item)
          end
          if not (paging and paging.next) then
            return 
          end
          local q = parse_query_string(parse_url(paging.next).query)
          after_value = q and q[paging_field]
          if not (after_value) then
            return 
          end
        end
      end)
    end,
    get_or_create_campaign_id = function(self, campaign_name)
      local campaign_id
      local _list_0 = assert(self:get_campaigns())
      for _index_0 = 1, #_list_0 do
        local c = _list_0[_index_0]
        if c.name == campaign_name then
          campaign_id = c.id
          break
        end
      end
      if not (campaign_id) then
        campaign_id = assert(self:create_campaign(campaign_name)).id
      end
      return campaign_id
    end,
    get_stats = function(self) end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, opts)
      if opts == nil then
        opts = { }
      end
      assert(opts.domain, "missing `domain` from opts")
      assert(opts.api_key, "missing `api_key` from opts")
      self.http_provider = opts.http
      self.domain = opts.domain
      self.api_key = opts.api_key
      self.default_sender = tostring(opts.domain) .. " <postmaster@" .. tostring(opts.domain) .. ">"
    end,
    __base = _base_0,
    __name = "Mailgun"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Mailgun = _class_0
end
return {
  Mailgun = Mailgun,
  VERSION = "1.0.0"
}
