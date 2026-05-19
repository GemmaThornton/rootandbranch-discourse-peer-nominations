import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";
import PeerNominateModal from "../../components/peer-nominate-modal";

export default class PeerNominateButton extends Component {
  @service modal;

  // Outlet context: { siteSettings, currentUser, model }.
  // model is the user whose profile is being viewed.
  static shouldRender(args, { siteSettings, currentUser }) {
    if (!siteSettings.peer_nominations_enabled) return false;
    if (!currentUser) return false;
    if (currentUser.id === args.model?.id) return false;
    return true;
  }

  get profileUser() {
    return this.args.model;
  }

  @action
  openModal() {
    this.modal.show(PeerNominateModal, {
      model: { profileUser: this.profileUser },
    });
  }

  <template>
    <button
      type="button"
      class="btn btn-default peer-nominate-btn"
      title={{i18n "peer_nominations.nominate_button_title"}}
      {{on "click" this.openModal}}
    >
      {{i18n "peer_nominations.nominate_button"}}
    </button>
  </template>
}
