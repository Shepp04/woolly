--!strict
export type DataConfig = {
    dataTemplate: { [string]: any },
    infoTemplate: { [string]: any },
}

local Data: DataConfig = {
    dataTemplate = {
        Stats = {},
        Analytics = {

        },
    },
    infoTemplate = {
        JoinTime = 0,
    },
}

return Data