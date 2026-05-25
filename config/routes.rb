# frozen_string_literal: true

PeerNominations::Engine.routes.draw do
  get  "/nominatable-badges"                            => "nominations#nominatable_badges"
  post "/"                                              => "nominations#create"
  post "/:topic_id/approve"                             => "nominations#approve"
  post "/:topic_id/decline"                             => "nominations#decline"
  post "/:topic_id/decline-as-nominee"                  => "nominations#decline_as_nominee"
  post "/:topic_id/add-nominee-to-national-group"       => "nominations#add_nominee_to_national_group"
  post "/:topic_id/add-nominee-to-district-group"       => "nominations#add_nominee_to_district_group"
  get  "/admin/users/:user_id/received"                 => "nominations#admin_received_for_user"
end

Discourse::Application.routes.draw do
  mount PeerNominations::Engine, at: "/peer-nominations"
end
