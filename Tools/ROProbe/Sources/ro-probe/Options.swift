import Foundation

/// Hand-parsed command line options. ArgumentParser is not a dependency of the repo packages.
struct Options {
    var host = "127.0.0.1"
    var port: UInt16 = 6900
    var user = "test"
    var pass = "test"
    var charName = "ProbeOne"
    var duration: TimeInterval = 60
    var chatInterval: TimeInterval = 30
    var walkInterval: TimeInterval = 3
    var attackInterval: TimeInterval = 5
    var jsonPath: String?
    var clientDir = "/Users/fwgl/Games/kRO_20210406/client"
    var deleteTest = false
    var reconnect = false
    var noTap = false
    var noEnterWorkaround = false
    var pincode: String?
    var withAudio = false
    var coverageOnly = false
    var tradeTest = false
    var chatRoomTest = false
    var route: [RouteStop] = []
    var maxReconnectBackoff: TimeInterval = 15
    var stageTimeout: TimeInterval = 120
    var mapLoadTimeout: TimeInterval = 300
    var vendingRole: String?
    var vendingTitle = "Probe potions"
    var vendingMap = "prt_fild08"
    var vendingX = 170
    var vendingY = 180
    var vendingTimeout: TimeInterval = 180

    static let usage = """
    Usage: ro-probe [options]

      --host <ip>             login server host            (default 127.0.0.1)
      --port <n>              login server port            (default 6900)
      --user <name>           account name                 (default test)
      --pass <password>       account password             (default test)
      --char-name <name>      character to use or create   (default ProbeOne)
      --duration <seconds>    time to stay on the map      (default 60)
      --chat-interval <s>     public chat period           (default 30)
      --walk-interval <s>     walk request period          (default 3)
      --attack-interval <s>   attack request period        (default 5)
      --json <path>           write the JSON summary here
      --client-dir <path>     kRO client directory with data.grf (default /Users/fwgl/Games/kRO_20210406/client)
      --delete-test           create a throwaway character, delete it, confirm it is gone
      --reconnect             on disconnect back off (1,2,4.. max 15 s) and redo login to map
      --no-tap                connect GameSession straight to the server (no per-opcode tally)
      --route <map:x,y;..>    walk to these cells on these maps (e.g. a warp) instead of wandering
      --no-enter-workaround  do not split the map CZ_ENTER from the packet that follows it (shows the client bug)
      --pincode <4 digits>    answer the char server pincode stages (enter, create, change) with this pin
      --stage-timeout <s>     wait per login stage         (default 120)
      --map-load-timeout <s>  wait for the map to load     (default 300)
      --with-audio            let the client play BGM and sound effects (muted by default)
      --vending <role>         run the vending scenario instead of wandering: seller, buyer, store-owner, store-seller
      --vending-title <text>   shop title the seller sets and the buyer expects (default "Probe potions")
      --vending-map <map>      map both probes warp to       (default prt_fild08)
      --vending-pos <x,y>      cell both probes warp to      (default 170,180)
      --vending-timeout <s>    how long to wait for the other probe (default 180)
      --coverage              print packet table coverage (P0-10) and exit
      --trade-test            two clients (trade1, trade2) trade items and zeny; --json writes the result
      --chatroom-test         two clients (room1, room2) use chat rooms: create, join, talk, rename, expel, give, leave; --json writes the result
      --chatroom-test         two clients (room1, room2) use a chat room: create, join, talk, rename, expel, give, leave; --json writes the result
      -h, --help              this text

    """

    /// A cell to walk to on a map, such as a warp, instead of wandering.
    struct RouteStop {
        var map: String
        var x: Int
        var y: Int
    }

    struct ParseError: Error, CustomStringConvertible {
        var description: String
    }

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0

        func value(_ flag: String) throws -> String {
            index += 1
            guard index < arguments.count else {
                throw ParseError(description: "missing value for \(flag)")
            }
            return arguments[index]
        }

        func number(_ flag: String) throws -> Double {
            let text = try value(flag)
            guard let number = Double(text) else {
                throw ParseError(description: "invalid number for \(flag): \(text)")
            }
            return number
        }

        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "--host": options.host = try value(flag)
            case "--port":
                guard let port = UInt16(try value(flag)) else {
                    throw ParseError(description: "invalid port")
                }
                options.port = port
            case "--user": options.user = try value(flag)
            case "--pass": options.pass = try value(flag)
            case "--char-name": options.charName = try value(flag)
            case "--duration": options.duration = try number(flag)
            case "--chat-interval": options.chatInterval = try number(flag)
            case "--walk-interval": options.walkInterval = try number(flag)
            case "--attack-interval": options.attackInterval = try number(flag)
            case "--json": options.jsonPath = try value(flag)
            case "--client-dir": options.clientDir = try value(flag)
            case "--delete-test": options.deleteTest = true
            case "--reconnect": options.reconnect = true
            case "--no-tap": options.noTap = true
            case "--no-enter-workaround": options.noEnterWorkaround = true
            case "--pincode": options.pincode = try value(flag)
            case "--route":
                // "iz_int:56,15;other_map:10,20". On a listed map the probe walks to that cell, not at random.
                for part in try value(flag).split(separator: ";") {
                    let pieces = part.split(separator: ":")
                    let cell = pieces.last?.split(separator: ",").compactMap { Int($0) } ?? []
                    guard pieces.count == 2, cell.count == 2 else {
                        throw ParseError(description: "invalid --route entry \(part), expected map:x,y")
                    }
                    options.route.append(RouteStop(map: String(pieces[0]), x: cell[0], y: cell[1]))
                }
            case "--stage-timeout": options.stageTimeout = try number(flag)
            case "--map-load-timeout": options.mapLoadTimeout = try number(flag)
            case "--with-audio": options.withAudio = true
            case "--vending":
                let role = try value(flag)
                guard ["seller", "buyer", "store-owner", "store-seller"].contains(role) else {
                    throw ParseError(description: "--vending expects seller, buyer, store-owner or store-seller, not \(role)")
                }
                options.vendingRole = role
            case "--vending-title": options.vendingTitle = try value(flag)
            case "--vending-map": options.vendingMap = try value(flag)
            case "--vending-pos":
                let cell = try value(flag).split(separator: ",").compactMap { Int($0) }
                guard cell.count == 2 else {
                    throw ParseError(description: "invalid --vending-pos, expected x,y")
                }
                options.vendingX = cell[0]
                options.vendingY = cell[1]
            case "--vending-timeout": options.vendingTimeout = try number(flag)
            case "--coverage": options.coverageOnly = true
            case "--trade-test": options.tradeTest = true
            case "--chatroom-test": options.chatRoomTest = true
            case "-h", "--help":
                print(usage)
                exit(0)
            default:
                throw ParseError(description: "unknown option \(flag)")
            }
            index += 1
        }

        return options
    }
}
