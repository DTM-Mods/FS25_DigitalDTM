-- Digital DTM (DTM Mods): the monitor's settings in multiplayer (picked storage, connected silos, screen
-- size, brightness, colours, title). A client sends them to the server, the server applies them and passes
-- them on to everyone, so all players see the same screen.

StorageMonitorSettingsEvent = {}
local StorageMonitorSettingsEvent_mt = Class(StorageMonitorSettingsEvent, Event)
InitEventClass(StorageMonitorSettingsEvent, "StorageMonitorSettingsEvent")

function StorageMonitorSettingsEvent.emptyNew()
    return Event.new(StorageMonitorSettingsEvent_mt)
end

function StorageMonitorSettingsEvent.new(placeable, settings)
    local self = StorageMonitorSettingsEvent.emptyNew()
    self.placeable = placeable
    self.settings = settings
    return self
end

function StorageMonitorSettingsEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    StorageMonitor.writeSettings(streamId, self.settings)
end

function StorageMonitorSettingsEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.settings = StorageMonitor.readSettings(streamId)
    self:run(connection)
end

function StorageMonitorSettingsEvent:run(connection)
    if self.placeable ~= nil and self.placeable.setStorageMonitorSettings ~= nil then
        self.placeable:setStorageMonitorSettings(self.settings, true)
    end
    if not connection:getIsServer() then
        g_server:broadcastEvent(StorageMonitorSettingsEvent.new(self.placeable, self.settings), nil, connection, self.placeable)
    end
end

function StorageMonitorSettingsEvent.sendEvent(placeable, settings, noEventSend)
    if noEventSend then
        return
    end
    local event = StorageMonitorSettingsEvent.new(placeable, settings)
    if g_server ~= nil then
        g_server:broadcastEvent(event, nil, nil, placeable)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(event)
    end
end
