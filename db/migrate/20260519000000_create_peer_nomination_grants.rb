# frozen_string_literal: true

class CreatePeerNominationGrants < ActiveRecord::Migration[7.0]
  def change
    create_table :peer_nomination_grants do |t|
      t.integer :nominator_id, null: false
      t.integer :nominee_id,   null: false
      t.integer :badge_id,     null: false
      t.integer :topic_id,     null: false
      t.integer :user_badge_id            # set after BadgeGranter runs; null if Discourse hasn't generated it yet
      t.text    :reason,       null: false # denormalised from the nomination topic for fast admin queries later
      t.datetime :granted_at,  null: false
      t.timestamps null: false
    end

    add_index :peer_nomination_grants, :nominator_id
    add_index :peer_nomination_grants, :nominee_id
    add_index :peer_nomination_grants, :badge_id
    add_index :peer_nomination_grants, :topic_id, unique: true

    # The key business rule: any one nominator can only successfully cause one grant
    # per (nominee, badge) pair. Multiple nominators can each grant the same badge
    # to the same person (because the badges are multiple_grant), which is the point.
    add_index :peer_nomination_grants,
              %i[nominator_id nominee_id badge_id],
              unique: true,
              name: "index_peer_nomination_grants_uniq_triple"
  end
end
