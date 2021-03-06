--[[
Title: Index table for sqlitestore
Author(s): LiXizhi, 
Date: 2016/5/11
Desc: 
use the lib:
------------------------------------------------------------
NPL.load("(gl)script/ide/System/Database/SqliteIndexTable.lua");
local IndexTable = commonlib.gettable("System.Database.SqliteStore.IndexTable");
------------------------------------------------------------
]]
local IndexTable = commonlib.inherit(nil, commonlib.gettable("System.Database.SqliteStore.IndexTable"));
local tostring = tostring;
local kIndexTableColumns = [[
	(name TEXT UNIQUE PRIMARY KEY,
	cid TEXT)]];

function IndexTable:ctor()
end

function IndexTable:init(name, parent)
	self.name = name;
	self.parent = parent;
	return self;
end

function IndexTable:GetDB()
	return self.parent._db;
end

function IndexTable:GetTableName()
	if(not self.tableName) then
		-- TODO: normalize name?
		self.tableName = self.name.."Index";
	end
	return self.tableName;
end

function IndexTable:CloseSQLStatement(name)
	if(self[name]) then
		self[name]:close();
		self[name] = nil;
	end
end

-- When sqlite_master table(schema) is changed, such as when new index table is created, 
-- all cached statements becomes invalid. And this function should be called to purge all statements created before.
function IndexTable:ClearStatementCache()
	self:CloseSQLStatement("add_stat");
	self:CloseSQLStatement("del_stat");
	self:CloseSQLStatement("sel_row_stat");
	self:CloseSQLStatement("select_stat");
	self:CloseSQLStatement("select_ids_stat");
	self:CloseSQLStatement("sel_all_stat");
	self:CloseSQLStatement("update_stat");
end

-- get first matching row id
-- @param value: value of the key to get
-- @return id: where id is the collection id number or nil if not found
function IndexTable:getId(value)
	local ids = self:getIds(value);
	if(ids) then
		return tonumber(ids:match("^%d+"));
	end
end

-- return all ids as commar separated string
function IndexTable:getIds(value)
	if(value) then
		value = tostring(value);
		self.select_stat = self.select_stat or self:GetDB():prepare([[SELECT cid FROM ]]..self:GetTableName()..[[ WHERE name=?]]);
		if(self.select_stat) then
			self.select_stat:bind(value);
			self.select_stat:reset();
			local row = self.select_stat:first_row();
			if(row) then
				return row.cid;
			end
		else
			LOG.std(nil, "error", "IndexTable", "failed to create select statement");
		end
	end
end

-- return the first matching row
-- return {id=number, value=string}. or nil if not exist.
function IndexTable:getRow(value)
	local id = self:getId(value);
	if(id) then
		self.sel_row_stat = self.sel_row_stat or self:GetDB():prepare([[SELECT * FROM Collection WHERE id=?]]);
		if(self.sel_row_stat) then
			self.sel_row_stat:bind(id);
			self.sel_row_stat:reset();
			return self.sel_row_stat:first_row();
		else
			LOG.std(nil, "error", "IndexTable", "failed to create select row statement");
		end
	end
end

-- this will remove the index to collection db for the given keyvalue. 
-- but it does not remove the real data item in collection db.
-- @param value: value of the key to remove
-- @param cid: default to nil. if not nil we will only remove when collection row id matches this one. 
function IndexTable:removeIndex(value, cid)
	if(value) then
		value = tostring(value);
		if(cid) then
			cid = tostring(cid);
			local ids = self:getIds(value);
			if(ids) then
				if(ids == cid) then
					self:removeIndex(value);
				else
					local new_ids = self:removeIdInIds(cid, ids);
					if(new_ids ~= ids) then
						if(new_ids ~= "") then
							self.update_stat = self.update_stat or self:GetDB():prepare([[UPDATE ]]..self:GetTableName()..[[  Set cid=? Where name=?]]);
							self.update_stat:bind(new_ids, value);
							self.update_stat:exec();
						else
							self:removeIndex(value);
						end
					else
						-- no index found
					end
				end
			end
		else
			self.del_stat = self.del_stat or self:GetDB():prepare([[DELETE FROM ]]..self:GetTableName()..[[ WHERE name=?]]);
			if(self.del_stat) then
				self.del_stat:bind(value);
				self.del_stat:exec();
			else
				LOG.std(nil, "error", "IndexTable", "failed to create delete statement");
			end
		end
	end
end

-- private:
-- @param cid, ids: must be string
-- return true if cid string is in ids string.
function IndexTable:hasIdInIds(cid, ids)
	if(cid == ids) then
		return true;
	else
		-- TODO: optimize this function with C++
		ids = ","..ids..",";
		return ids:match(","..cid..",") ~= nil;
	end
end

-- private:
-- @param cid, ids: must be string
-- @return ids: new ids with cid removed
function IndexTable:removeIdInIds(cid, ids)
	if(cid == ids) then
		return "";
	else
		-- TODO: optimize this function with C++
		local tmp_ids = ","..ids..",";
		local new_ids = tmp_ids:gsub(",("..cid..",)", "");
		if(new_ids~=tmp_ids) then
			return new_ids:gsub("^,", ""):gsub(",$", "");
		else
			return ids;
		end
	end
end

function IndexTable:addIdToIds(cid, ids)
	return ids..(","..cid)
end

-- private:
-- get id maps from ids string
-- @param ids: must be string
-- @return a table containing mapping from number cid to true
function IndexTable:getMapFromIds(ids)
	local map = {};
	for id in ids:gmatch("%d+") do
		map[tonumber(id)] = true;
	end
	return map;
end

-- private: 
-- get array from ids string
-- @param ids: must be string
-- @return a array table containing all number cid
function IndexTable:getArrayFromIds(ids)
	local array= {};
	for id in ids:gmatch("%d+") do
		array[#array+1] = tonumber(id);
	end
	return array;
end

-- add index to collection row id
-- @param value: value of the key 
-- @param cid: collection row id
function IndexTable:addIndex(value, cid)
	if(value and cid) then
		value = tostring(value);
		cid = tostring(cid);
		local ids = self:getIds(value);
		if(not ids) then
			self.add_stat = self.add_stat or self:GetDB():prepare([[INSERT INTO ]]..self:GetTableName()..[[(name, cid) VALUES (?, ?)]]);
			self.add_stat:bind(value, cid);
			self.add_stat:exec();
		elseif(ids ~= cid and not self:hasIdInIds(cid, ids)) then
			ids = self:addIdToIds(cid, ids);
			self.update_stat = self.update_stat or self:GetDB():prepare([[UPDATE ]]..self:GetTableName()..[[  Set cid=? Where name=?]]);
			self.update_stat:bind(ids, value);
			self.update_stat:exec();
		end
	end
end

-- creating index for existing rows
function IndexTable:CreateTable()
	self.parent:FlushAll();

	local stat = self:GetDB():prepare([[INSERT INTO Indexes (name, tablename) VALUES (?, ?)]]);
	stat:bind(self.name, self:GetTableName());
	stat:exec();
	stat:close();

	local sql = "CREATE TABLE IF NOT EXISTS ";
	sql = sql..self:GetTableName().." "
	sql = sql..kIndexTableColumns;
	self:GetDB():exec(sql);
	
	-- rebuild all indices
	NPL.load("(gl)script/ide/System/Database/Item.lua");
	local Item = commonlib.gettable("System.Database.Item");
	local item = Item:new();
	
	local indexmap = {};
	local name = self.name;
	self.parent:find({}, function(err, rows)
		if(rows) then
			for _, row in ipairs(rows) do
				if(row and row[name]) then
					local keyValue = tostring(row[name])
					if(keyValue~="") then
						if(not indexmap[keyValue]) then
							indexmap[keyValue] = tostring(row._id);
						else
							indexmap[keyValue] = indexmap[keyValue]..(","..tostring(row._id));
						end
					end
				end
			end
		end
	end)

	self.parent:Begin();
	local count = 0;
	local stmt = self:GetDB():prepare([[INSERT INTO ]]..self:GetTableName()..[[ (name, cid) VALUES (?, ?)]]);
	for name, cid in pairs(indexmap) do
		stmt:bind(name, cid);
		stmt:exec();
		count = count + 1;
	end
	stmt:close();
	LOG.std(nil, "info", "SqliteStore", "index table is created for `%s` with %d records", self.name, count);
	self.parent:End();
	self.parent:FlushAll();
	self.parent:ClearStatementCache();
end

function IndexTable:Destroy()
	self.parent:FlushAll();
	self:GetDB():exec(format("DELETE FROM Indexes WHERE name='%s'", self.name));
	-- NOTE: for unknown reasons, if we drop table, the next find operation return nothing, even we reopen the database. 
	-- self:GetDB():exec("DROP TABLE "..self:GetTableName()); self.parent:Reopen();
	-- so instead of dropping tables, we simply remove all data in it. 
	self:GetDB():exec("DELETE FROM "..self:GetTableName());
	LOG.std(nil, "info", "SqliteStore", "index `%s` removed from %s", self.name, self.parent:GetFileName());
	self.parent:ClearStatementCache();
end