
Character = require "./../base/Character"
RestrictedNumber = require "restricted-number"
MessageCreator = require "../../system/MessageCreator"
Constants = require "../../system/Constants"
Equipment = require "../../item/Equipment"
_ = require "underscore"
Personality = require "../base/Personality"

Chance = require "chance"
chance = new Chance()

class Player extends Character

  isBusy: false

  constructor: (player) ->
    super player

  initialize: ->
    if not @xp
      @xp = new RestrictedNumber 0, (@levelUpXpCalc 0), 0
      @gold = new RestrictedNumber 0, 9999999999, 0
      @x = 10
      @y = 10
      @map = 'Norkos'
      @changeProfession "Generalist", yes
      @levelUp yes
      @generateBaseEquipment()

  generateBaseEquipment: ->
    @equipment = [
      new Equipment {type: "body",    class: "Newbie", name: "Tattered Shirt", con: 1}
      new Equipment {type: "feet",    class: "Newbie", name: "Cardboard Shoes", dex: 1}
      new Equipment {type: "finger",  class: "Newbie", name: "Twisted Wire", int: 1}
      new Equipment {type: "hands",   class: "Newbie", name: "Pixelated Gloves", str: 1}
      new Equipment {type: "head",    class: "Newbie", name: "Miniature Top Hat", wis: 1}
      new Equipment {type: "legs",    class: "Newbie", name: "Leaf", agi: 1}
      new Equipment {type: "neck",    class: "Newbie", name: "Old Brooch", wis: 1, int: 1}
      new Equipment {type: "mainhand",class: "Newbie", name: "Empty and Broken Ale Bottle", str: 1, con: -1}
      new Equipment {type: "offhand", class: "Newbie", name: "Chunk of Rust", dex: 1, str: 1}
      new Equipment {type: "charm",   class: "Newbie", name: "Ancient Bracelet", con: 1, dex: 1}
    ]

  handleTrainerOnTile: (tile) ->
    return if @isBusy
    @isBusy = true
    className = tile.object.name
    message = "#{@name} has met with the #{className} trainer!"
    if @professionName is className
      message += " Alas, #{@name} is already a #{className}!"
      @isBusy = false
      @emit "trainer.isAlready", className
      
    @playerManager.game.broadcast MessageCreator.genericMessage message

    if @professionName isnt className
      @playerManager.game.eventHandler.doYesNo {}, @, (result) =>
        @isBusy = false
        if not result
          @emit "trainer.ignore", className
          return
          
        @emit "trainer.speak", className
        @changeProfession className



  handleTeleport: (tile) ->
    dest = tile.object.properties
    dest.x = parseInt dest.x
    dest.y = parseInt dest.y

    if not dest.map
      console.error "ERROR. No dest.map at #{@x},#{@y} in #{@map}"
      return

    @map = dest.map
    @x = dest.x
    @y = dest.y

    message = ""

    switch dest.movementType
      when "ascend" then message = "#{@name} has ascended to #{dest.destName}."
      when "descend" then message = "#{@name} has descended to #{dest.destName}."

    @emit dest.movementType

    @playerManager.game.broadcast MessageCreator.genericMessage message

  handleTile: (tile) ->
    switch tile.object?.type
      when "Trainer" then @handleTrainerOnTile tile
      when "Teleport" then @handleTeleport tile

  moveAction: ->
    randomDir = -> chance.integer({min: 1, max: 9})
    dir = randomDir()
    dir = randomDir() while dir is @ignoreDir

    dir = if chance.bool {likelihood: 75} then @lastDir else dir
    newLoc = @num2dir dir, @x, @y

    tile = @playerManager.game.world.maps[@map].getTile newLoc.x,newLoc.y
    if not tile.blocked
      @x = newLoc.x
      @y = newLoc.y
      @lastDir = dir
      @ignoreDir = null

      @emit 'walk'
      @emit "on.#{tile.terrain}"

    else
      @lastDir = null
      @ignoreDir = dir

      @emit 'hit.wall'

    @handleTile tile

  changeProfession: (to, suppress = no) ->
    oldProfessionName = @professionName
    professionProto = require "../classes/#{to}"
    @profession = new professionProto()
    @professionName = professionProto.name
    @profession.load @
    @playerManager.game.broadcast MessageCreator.genericMessage "#{@name} is now a #{to}!" if not suppress
    @emit "profession.change", oldProfessionName, @professionName

    @recalculateStats()

  calculateYesPercent: ->
    Math.min 100, (Math.max 0, Constants.defaults.player.defaultYesPercent + @personalityReduce 'calculateYesPercentBonus')

  calculatePartyLeavePercent: ->
    Math.min 100, (Math.max 0, Constants.defaults.player.defaultPartyLeavePercent + @personalityReduce 'partyLeaveProbabilityBonus')

  getGender: ->
    "male"

  possiblyDoEvent: ->
    event = Constants.pickRandomEvent @
    return if not event
    @playerManager.game.eventHandler.doEvent event, @, ->{} #god damned code collapse

  possiblyLeaveParty: ->
    return if not @party
    return if @party.currentBattle
    return if not chance.bool {likelihood: @calculatePartyLeavePercent()}
    @party.playerLeave @

  takeTurn: ->
    @moveAction()
    @possiblyDoEvent()
    @possiblyLeaveParty()
    @save()

  save: ->
    return if not @playerManager
    @playerManager.savePlayer @

  gainGold: (gold) ->
    if gold > 0
      @emit "gold.gain", gold
    else
      @emit "gold.lose", gold

    @gold.add gold

  gainXp: (xp) ->
    if xp > 0
      @emit "xp.gain", xp
    else
      @emit "xp.lose", xp

    @xp.set 0 if _.isNaN @xp.__current
    @xp.add xp

    if @xp.atMax()
      @levelUp()

  levelUp: (suppress = no) ->
    return if not @playerManager
    @level.add 1
    @playerManager.game.broadcast MessageCreator.genericMessage "#{@name} has attained level #{@level.getValue()}!" if not suppress
    @xp.maximum = @levelUpXpCalc @level.getValue()
    @xp.toMinimum()
    @emit "level.up"
    @recalculateStats()

  levelUpXpCalc: (level) ->
    Math.floor 100 + (400 * Math.pow level, 1.71)

  itemFindRange: ->
    (@level.getValue()+1) * @calc.itemFindRangeMultiplier()

  recalculateStats: ->
    @hp.maximum = @calc.hp()
    @mp.maximum = @calc.mp()
    @special.maximum = @calc.special()

module.exports = exports = Player
