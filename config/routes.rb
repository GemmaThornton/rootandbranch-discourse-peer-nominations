# frozen_string_literal: true

PeerNominations::Engine.routes.draw do
  get  "/nominatable-badges"           => "nominations#nominatable_badges"
  post "/"                             => "nominations#create"
  post "/:topic_id/approve"            => "nominations#approve"
  post "/:topic_id/decline"            => "nominations#decline"
end

Discourse::Application.routes.draw do
  mount PeerNominations::Engine, at: "/peer-nominations"
end
