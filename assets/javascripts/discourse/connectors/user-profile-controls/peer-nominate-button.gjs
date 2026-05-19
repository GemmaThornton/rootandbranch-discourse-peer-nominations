import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";
import PeerNominateModal from "../../components/peer-nominate-modal";

export default class PeerNominateButton extends Component {
  @service modal;
  @service currentUser;

  // Outlet context: { siteSettings, currentUser, model }.
  // model is the user whose profile is being viewed. We render on every
  // user's profile (including the current user's own) — self-nominations
  // are allowed and gated by admin review.
  static shouldRender(args, { siteSettings, currentUser }) {
    if (!siteSettings.peer_nominations_enabled) return false;
    if (!currentUser) return false;
    return true;
  }

  get profileUser() {
    return this.args.model;
  }

  get isSelf() {
    return this.currentUser?.id === this.profileUser?.id;
  }

  get buttonLabel() {
    return this.isSelf
      ? i18n("peer_nominations.nominate_button_self")
      : i18n("peer_nominations.nominate_button");
  }

  get buttonTitle() {
    return this.isSelf
      ? i18n("peer_nominations.nominate_button_title_self")
      : i18n("peer_nominations.nominate_button_title");
  }

  @action
  openModal() {
    this.modal.show(PeerNominateModal, {
      model: {
        profileUser: this.profileUser,
        isSelf: this.isSelf,
      },
    });
  }

  <template>
    <button
      type="button"
      class="btn btn-default peer-nominate-btn"
      title={{this.buttonTitle}}
      {{on "click" this.openModal}}
    >
      {{this.buttonLabel}}
    </button>
  </template>
}
