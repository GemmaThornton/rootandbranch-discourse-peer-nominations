# frozen_string_literal: true

class PeerNominationGrant < ActiveRecord::Base
  belongs_to :nominator, class_name: "User"
  belongs_to :nominee,   class_name: "User"
  belongs_to :badge
  belongs_to :topic
  belongs_to :user_badge, optional: true

  validates :nominator_id, presence: true
  validates :nominee_id,   presence: true
  validates :badge_id,     presence: true
  validates :topic_id,     presence: true, uniqueness: true
  validates :reason,       presence: true
  validates :granted_at,   presence: true
  validates :nominator_id, uniqueness: { scope: %i[nominee_id badge_id] }

  # Per-nominee visibility scope, set when the nominee acts on the
  # approval PM. Default 'public' (badge visible to everyone, the
  # original behaviour). Other values narrow who can see the badge —
  # see PeerNominations::BadgeVisibility for the filter logic.
  VISIBILITY_SCOPES = %w[public vs_only admin_only].freeze
  validates :visibility_scope, inclusion: { in: VISIBILITY_SCOPES }
end
